local grid = require("math-conceal.image.grid")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local tracker = require("math-conceal.image.tracker")

local M = {}

M.SLOT_PRIORITY = 230
M.CONCEAL_PRIORITY = 225

local surfaces_by_win = {}
local capability = nil

local function valid_buf(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

function M.available()
  if capability ~= nil then
    return capability
  end
  if type(vim.api.nvim__ns_set) ~= "function" or type(vim.api.nvim_win_text_height) ~= "function" then
    capability = false
    return false
  end
  local winid = vim.api.nvim_get_current_win()
  local ns = vim.api.nvim_create_namespace("math-conceal.image.placement.surface.capability")
  capability = valid_win(winid) and pcall(vim.api.nvim__ns_set, ns, { wins = { winid } })
  return capability
end

function M.text_width(surface)
  if surface == nil or not valid_win(surface.win) then
    return 1
  end
  local info = vim.fn.getwininfo(surface.win)[1] or {}
  return math.max(1, vim.api.nvim_win_get_width(surface.win) - (tonumber(info.textoff) or 0))
end

function M.line(surface, row)
  if surface == nil or not valid_buf(surface.bufnr) then
    return ""
  end
  return tracker.source_line(surface.bufnr, row)
end

function M.line_len(surface, row)
  return #M.line(surface, row)
end

function M.source_prefix_width(surface, row, col)
  if col == nil or col <= 0 then
    return 0
  end
  return math.max(0, vim.fn.strdisplaywidth(M.line(surface, row):sub(1, col)))
end

function M.effective_grid(surface, request)
  local natural = request and request.natural_grid or nil
  local cols, rows = grid.clamp(natural and natural.cols or 1, natural and natural.rows or 1)
  if request ~= nil and request.display_kind == "block" then
    local fit = request.placement_style and request.placement_style.fit or {}
    local left = math.max(0, math.floor(tonumber(fit.left_padding_cols) or 0))
    local right = math.max(0, math.floor(tonumber(fit.right_padding_cols) or 0))
    cols = math.min(cols, math.max(1, M.text_width(surface) - left - right))
  end
  return { cols = cols, rows = rows }
end

local function delete_extmark(surface, id)
  if id ~= nil and surface ~= nil and valid_buf(surface.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, surface.bufnr, surface.ns, id)
  end
end

function M.clear_artifacts(surface, record)
  if record == nil then
    return
  end
  for _, id in ipairs(record.extmark_ids or {}) do
    delete_extmark(surface, id)
  end
  record.extmark_ids = {}
end

function M.artifacts_valid(surface, record)
  if surface == nil or record == nil or #(record.extmark_ids or {}) == 0 or not valid_buf(surface.bufnr) then
    return false
  end
  for _, id in ipairs(record.extmark_ids) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(surface.bufnr, surface.ns, id, { details = true })
    if mark[1] == nil or ((mark[3] or {}).invalid == true) then
      return false
    end
  end
  return true
end

function M.add_extmark(surface, row, col, opts)
  return vim.api.nvim_buf_set_extmark(surface.bufnr, surface.ns, row, col, opts)
end

function M.clear_range(surface, view)
  if surface ~= nil and view ~= nil and valid_buf(surface.bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, surface.bufnr, surface.ns, view.row, view.end_row + 1)
  end
end

function M.redraw(surface, start_row, end_row)
  if
    surface == nil
    or type(vim.api.nvim__redraw) ~= "function"
    or not valid_win(surface.win)
    or not valid_buf(surface.bufnr)
  then
    return
  end
  start_row = math.max(0, math.floor(tonumber(start_row) or 0))
  end_row = math.max(start_row, math.floor(tonumber(end_row) or start_row))
  pcall(vim.api.nvim__redraw, {
    win = surface.win,
    range = { start_row, end_row + 1 },
    valid = false,
    flush = true,
  })
end

function M.release_terminal(record)
  if record == nil or record.placement_id == nil then
    return
  end
  terminal.delete_placement(record.image_id, record.placement_id)
  record.placement_id = nil
end

function M.deactivate(surface, record, opts)
  if record == nil then
    return
  end
  opts = opts or {}
  local start_row, end_row = record.source_start_row, record.source_end_row
  local had_artifacts = #(record.extmark_ids or {}) > 0
  M.clear_artifacts(surface, record)
  if opts.keep_terminal ~= true then
    M.release_terminal(record)
  end
  record.placed = false
  if had_artifacts and start_row ~= nil and end_row ~= nil then
    M.redraw(surface, start_row, end_row)
  end
end

function M.ensure_terminal(record)
  if record == nil or record.image_id == nil or record.grid == nil then
    return false
  end
  if record.placement_id == nil then
    record.placement_id = state.allocate_placement_id(record.bufnr)
  end
  record.hl = state.placement_hl_group(record.image_id, record.placement_id)
  return terminal.place_image(record.image_id, record.placement_id, record.grid.cols, record.grid.rows, { C = 1 })
end

function M.ensure(winid, bufnr)
  if not M.available() or not valid_win(winid) or not valid_buf(bufnr) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end
  local existing = surfaces_by_win[winid]
  if existing ~= nil and existing.bufnr ~= bufnr then
    M.close(existing)
    existing = nil
  end
  if existing ~= nil and existing.closed ~= true then
    return existing
  end

  local ns = vim.api.nvim_create_namespace("math-conceal.image.placement.surface." .. bufnr .. "." .. winid)
  if not pcall(vim.api.nvim__ns_set, ns, { wins = { winid } }) then
    return nil
  end
  local surface = {
    win = winid,
    bufnr = bufnr,
    ns = ns,
    records = {},
    closed = false,
  }
  surfaces_by_win[winid] = surface
  return surface
end

function M.update_record(surface, key, request)
  local record = surface.records[key]
  if record == nil then
    record = {
      bufnr = surface.bufnr,
      key = key,
      extmark_ids = {},
    }
    surface.records[key] = record
  elseif
    request.state == "ready"
    and record.image_id ~= nil
    and request.image_id ~= nil
    and record.image_id ~= request.image_id
  then
    M.deactivate(surface, record)
  end
  record.request = vim.deepcopy(request)
  if request.state == "ready" then
    record.image_id = request.image_id
    record.realization_key = request.realization_key
    record.grid = M.effective_grid(surface, request)
  end
  return record
end

function M.close_record(surface, key)
  local record = surface and surface.records and surface.records[key] or nil
  if record == nil then
    return
  end
  M.deactivate(surface, record)
  surface.records[key] = nil
end

function M.release_image(image_id)
  for _, surface in pairs(surfaces_by_win) do
    for _, record in pairs(surface.records or {}) do
      if record.image_id == image_id then
        M.deactivate(surface, record)
        record.image_id = nil
        record.grid = nil
        record.request = { state = "source", ref = record.request and record.request.ref, reason = "evicted" }
      end
    end
  end
end

function M.close(surface)
  if surface == nil or surface.closed == true then
    return
  end
  surface.closed = true
  for key in pairs(vim.deepcopy(surface.records or {})) do
    M.close_record(surface, key)
  end
  if valid_buf(surface.bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, surface.bufnr, surface.ns, 0, -1)
  end
  if surfaces_by_win[surface.win] == surface then
    surfaces_by_win[surface.win] = nil
  end
end

function M.close_window(winid, owner_bufnr)
  local surface = surfaces_by_win[winid]
  if surface == nil or (owner_bufnr ~= nil and surface.bufnr ~= owner_bufnr) then
    return false
  end
  M.close(surface)
  return true
end

function M.close_buffer(bufnr)
  local closing = {}
  for _, surface in pairs(surfaces_by_win) do
    if surface.bufnr == bufnr then
      closing[#closing + 1] = surface
    end
  end
  for _, surface in ipairs(closing) do
    M.close(surface)
  end
end

local function is_blank(text)
  return (text or ""):match("^%s*$") ~= nil
end

local function add_fragment(fragments, row, col, end_col, line)
  local prefix = line:sub(1, col)
  local suffix = line:sub(end_col + 1)
  fragments[#fragments + 1] = {
    row = row,
    col = col,
    end_col = math.max(col, end_col),
    empty_row = #line == 0 and col == 0 and end_col == 0,
    fragment_only = is_blank(prefix) and is_blank(suffix),
  }
end

function M.source_fragments(surface, view, display_kind)
  local start_line = M.line(surface, view.row)
  if view.row == view.end_row then
    local fragments = {}
    add_fragment(fragments, view.row, view.col, view.end_col, start_line)
    return fragments
  end

  local end_line = M.line(surface, view.end_row)
  local absorbed_end_col = view.end_col
  if display_kind == "inline" then
    local suffix = end_line:sub(view.end_col + 1)
    absorbed_end_col = view.end_col + #(suffix:match("^[ \t]*") or "")
  end

  local fragments = {}
  add_fragment(fragments, view.row, view.col, #start_line, start_line)
  for row = view.row + 1, view.end_row - 1 do
    local line = M.line(surface, row)
    add_fragment(fragments, row, 0, #line, line)
  end
  add_fragment(fragments, view.end_row, 0, absorbed_end_col, end_line)
  return fragments
end

function M.placeholder_line(record, image_row, prefix_cols)
  prefix_cols = math.max(0, math.floor(tonumber(prefix_cols) or 0))
  local chunks = {}
  if prefix_cols > 0 then
    chunks[#chunks + 1] = { string.rep(" ", prefix_cols), "" }
  end
  chunks[#chunks + 1] = { grid.placeholder_row(image_row, record.grid.cols), record.hl }
  return chunks
end

function M.conceal_fragment(surface, fragment, carries_slot, ids)
  if fragment.fragment_only and not carries_slot then
    ids[#ids + 1] = M.add_extmark(surface, fragment.row, 0, {
      conceal_lines = "",
      end_row = fragment.row,
      invalidate = true,
      priority = M.CONCEAL_PRIORITY,
    })
    return
  end
  if fragment.end_col <= fragment.col then
    return
  end
  ids[#ids + 1] = M.add_extmark(surface, fragment.row, fragment.col, {
    end_row = fragment.row,
    end_col = fragment.end_col,
    conceal = "",
    invalidate = true,
    priority = M.CONCEAL_PRIORITY,
  })
end

function M.source_cols(view, row)
  if view == nil or row < view.row or row > view.end_row then
    return nil, nil
  end
  if view.row == view.end_row then
    return view.col, view.end_col
  end
  if row == view.row then
    return view.col, math.huge
  end
  if row == view.end_row then
    return 0, view.end_col
  end
  return 0, math.huge
end

function M._state()
  return { available = M.available(), surfaces_by_win = surfaces_by_win }
end

function M._reset_capability()
  capability = nil
end

return M
