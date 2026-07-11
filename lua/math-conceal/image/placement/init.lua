local boundary_block = require("math-conceal.image.placement.strategy.boundary-block")
local conflict = require("math-conceal.image.placement.conflict")
local inline = require("math-conceal.image.placement.strategy.inline")
local isolated_block = require("math-conceal.image.placement.strategy.isolated-block")
local surface_api = require("math-conceal.image.placement.surface")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")
local tracker = require("math-conceal.image.tracker")

local M = {}

local strategies = {
  inline = inline,
  isolated = isolated_block,
  prefix = boundary_block,
  suffix = boundary_block,
}

local function normalize_request(request)
  if type(request) ~= "table" or type(request.ref) ~= "table" then
    return nil
  end
  if request.state == "source" then
    return {
      state = "source",
      ref = vim.deepcopy(request.ref),
      reason = request.reason,
    }
  end
  if
    request.state ~= "ready"
    or request.image_id == nil
    or request.realization_key == nil
    or type(request.natural_grid) ~= "table"
    or (request.display_kind ~= "inline" and request.display_kind ~= "block")
  then
    return nil
  end
  if request.display_kind == "inline" and request.source_boundary_role ~= nil then
    return nil
  end
  if
    request.display_kind == "block"
    and request.source_boundary_role ~= "isolated"
    and request.source_boundary_role ~= "prefix"
    and request.source_boundary_role ~= "suffix"
    and request.source_boundary_role ~= "sandwich"
  then
    return nil
  end
  return vim.deepcopy(request)
end

local function visual_selection(winid)
  if vim.api.nvim_get_current_win() ~= winid then
    return nil
  end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local mark = vim.fn.getpos("v")
  local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
  local mark_row, mark_col = mark[2] - 1, math.max(0, mark[3] - 1)
  if mode == "V" then
    return { mode = "line", start_row = math.min(mark_row, cursor_row), end_row = math.max(mark_row, cursor_row) }
  end
  if mode == "\22" then
    return {
      mode = "block",
      start_row = math.min(mark_row, cursor_row),
      end_row = math.max(mark_row, cursor_row),
      start_col = math.min(mark_col, cursor_col),
      end_col = math.max(mark_col, cursor_col) + 1,
    }
  end
  local start_row, start_col = mark_row, mark_col
  local end_row, end_col = cursor_row, cursor_col + 1
  if end_row < start_row or (end_row == start_row and end_col < start_col) then
    start_row, start_col, end_row, end_col = end_row, end_col, start_row, start_col
  end
  return {
    mode = "char",
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

local function strategy_for(request)
  if request.display_kind == "inline" then
    return inline, "inline"
  end
  local role = request.source_boundary_role
  return strategies[role], role
end

local function resolve_views(surface)
  local views = {}
  for key, record in pairs(surface.records) do
    views[key] = track_view.for_ref(record.request and record.request.ref, { require_valid = true })
  end
  return views
end

local function visibility_state(surface, conceal_in_normal)
  local cursor = vim.api.nvim_win_get_cursor(surface.win)
  local mode = vim.api.nvim_get_mode().mode or ""
  local views = resolve_views(surface)
  local source = conflict.resolve(surface.records, views, {
    cursor = { row = cursor[1] - 1, col = cursor[2] },
    selection = visual_selection(surface.win),
    mode = mode,
    conceal_in_normal = conceal_in_normal == true,
  })
  return views, source
end

local function source_signature(record)
  return table.concat({ "source", tostring(record.image_id or ""), tostring(record.realization_key or "") }, ":")
end

local function apply_record(surface, record, view, show_source, force_geometry)
  if show_source or view == nil then
    local signature = source_signature(record)
    if record.signature ~= signature or record.placed == true or #(record.extmark_ids or {}) > 0 then
      surface_api.deactivate(surface, record, { keep_terminal = record.image_id ~= nil })
      record.signature = signature
    end
    record.source_visible = true
    return true
  end

  local strategy, strategy_name = strategy_for(record.request)
  if strategy == nil then
    surface_api.deactivate(surface, record, { keep_terminal = record.image_id ~= nil })
    record.source_visible = true
    record.signature = source_signature(record)
    return true
  end

  if strategy.prepare_measure ~= nil then
    strategy.prepare_measure(surface, record, view)
  end
  local layout = strategy.measure(surface, record, view)
  if layout == nil then
    surface_api.deactivate(surface, record, { keep_terminal = record.image_id ~= nil })
    record.source_visible = true
    record.signature = source_signature(record)
    return false
  end
  local signature = strategy.signature(record, layout)
  if
    force_geometry ~= true
    and record.signature == signature
    and record.placed == true
    and surface_api.artifacts_valid(surface, record)
  then
    record.source_visible = false
    return true
  end
  record.strategy = strategy_name
  record.source_visible = false
  return strategy.apply(surface, record, view, layout)
end

function M.reconcile_window(winid, transaction)
  transaction = transaction or {}
  local existing = surface_api._state().surfaces_by_win[winid]
  local bufnr = existing and existing.bufnr or nil
  for _, request in pairs(transaction.upsert or {}) do
    if request.ref ~= nil and request.ref.bufnr ~= nil then
      bufnr = request.ref.bufnr
      break
    end
  end
  if bufnr == nil then
    return false
  end
  local surface = surface_api.ensure(winid, bufnr)
  if surface == nil then
    return false
  end

  local changed = {}
  for key in pairs(transaction.close or {}) do
    surface_api.close_record(surface, key)
  end
  for supplied_key, request in pairs(transaction.upsert or {}) do
    local normalized = normalize_request(request)
    if normalized ~= nil then
      local key = tracker.track_ref_key(normalized.ref)
      if supplied_key == key or supplied_key == nil then
        surface_api.update_record(surface, key, normalized)
        changed[key] = true
      end
    end
  end
  for key in pairs(transaction.refresh or {}) do
    changed[key] = true
  end

  local views, source = visibility_state(surface, transaction.conceal_in_normal)
  for key, record in pairs(surface.records) do
    local desired_source = source[key] == true
    if record.source_visible ~= desired_source then
      changed[key] = true
    end
  end

  local function commit()
    for key in pairs(changed) do
      local record = surface.records[key]
      if record ~= nil then
        apply_record(surface, record, views[key], source[key] == true, transaction.refresh and transaction.refresh[key])
      end
    end
  end
  if type(terminal.batch) == "function" then
    terminal.batch(commit)
  else
    commit()
  end
  return true
end

function M.close_window(winid)
  surface_api.close_window(winid)
end

function M.close_buffer(bufnr)
  surface_api.close_buffer(bufnr)
end

function M.release_image(image_id)
  surface_api.release_image(image_id)
end

function M.available()
  return surface_api.available()
end

function M._state()
  return { surface = surface_api._state() }
end

return M
