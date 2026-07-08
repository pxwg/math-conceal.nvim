local context = require("math-conceal.image.context")
local display = require("math-conceal.image.display")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")
local tracker = require("math-conceal.image.tracker")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function valid_loaded_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

local function is_insert_like_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode or ""
  return mode:find("i", 1, true) ~= nil or mode:find("R", 1, true) ~= nil
end

local function is_presentation_mode(bufnr)
  local ok, render = pcall(require, "math-conceal.render")
  if not ok or type(render.is_presentation_mode) ~= "function" then
    return false
  end
  local ok_mode, enabled = pcall(render.is_presentation_mode, bufnr)
  return ok_mode and enabled == true
end

local function active_window_for_bufnr(bufnr)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current) and vim.api.nvim_win_get_buf(current) == bufnr then
    return current
  end

  local wins = vim.fn.win_findbuf(bufnr)
  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end
  return nil
end

local function cursor_in_range(track, row, col, opts)
  opts = opts or {}
  if track == nil then
    return false
  end

  local sr, sc, er, ec = track.row, track.col, track.end_row, track.end_col
  if row < sr or row > er then
    return false
  end

  local include_right_edge = opts.include_right_edge == true
  if sr == er then
    if include_right_edge then
      return col >= sc and col <= ec
    end
    return col >= sc and col < ec
  end
  if row == sr then
    return col >= sc
  end
  if row == er then
    if include_right_edge then
      return col <= ec
    end
    return col < ec
  end
  return true
end

local function cursor_near_range(range, row, col)
  if range == nil or row < range.row or row > range.end_row then
    return false
  end

  local slack_cols = 8
  if range.row == range.end_row then
    return col >= math.max(0, range.col - 1) and col <= math.max(range.end_col, range.col) + slack_cols
  end
  if row == range.row then
    return col >= math.max(0, range.col - 1)
  end
  if row == range.end_row then
    return col <= range.end_col + slack_cols
  end
  return true
end

local function track_span(track)
  return (track.end_row - track.row) * 100000 + (track.end_col - track.col)
end

local function projection_at_cursor(bufnr, row, col, mode, tracks_by_key)
  local bs = state.get_buf_state(bufnr)
  local best = nil
  for _, projection in pairs(bs.projections or {}) do
    local track = track_view.for_projection(projection, {
      by_key = tracks_by_key,
      require_valid = true,
    })
    if
      track ~= nil
      and track.node_type == "math"
      and cursor_in_range(track, row, col, { include_right_edge = is_insert_like_mode(mode) })
    then
      if best == nil or track_span(track) > track_span(best.track) then
        best = { projection = projection, track = track }
      end
    end
  end
  if best == nil then
    return nil, nil
  end
  return best.projection, best.track
end

local function range_object(track)
  return {
    row = track.row,
    col = track.col,
    end_row = track.end_row,
    end_col = track.end_col,
  }
end

local function track_contains_range(track, start_row, start_col, end_row, end_col)
  if track == nil then
    return false
  end
  local start_ok = start_row > track.row or (start_row == track.row and start_col >= track.col)
  local end_ok = end_row < track.end_row or (end_row == track.end_row and end_col <= track.end_col)
  return start_ok and end_ok and (start_row < end_row or start_col <= end_col)
end

local function track_relative_col(track, row, col)
  if row == track.row then
    return col - track.col
  end
  return col
end

local function track_source_slice(track, start_row, start_col, end_row, end_col)
  local source = track and track.source or ""
  if source == "" or not track_contains_range(track, start_row, start_col, end_row, end_col) then
    return nil
  end

  local lines = vim.split(source, "\n", { plain = true })
  local start_idx = start_row - track.row + 1
  local end_idx = end_row - track.row + 1
  if start_idx < 1 or end_idx > #lines or start_idx > end_idx then
    return nil
  end

  local rel_start_col = math.max(0, track_relative_col(track, start_row, start_col))
  local rel_end_col = math.max(0, track_relative_col(track, end_row, end_col))
  if start_idx == end_idx then
    local line = lines[start_idx] or ""
    rel_start_col = math.min(rel_start_col, #line)
    rel_end_col = math.max(rel_start_col, math.min(rel_end_col, #line))
    return line:sub(rel_start_col + 1, rel_end_col)
  end

  local out = {}
  local first = lines[start_idx] or ""
  local last = lines[end_idx] or ""
  out[#out + 1] = first:sub(math.min(rel_start_col, #first) + 1)
  for idx = start_idx + 1, end_idx - 1 do
    out[#out + 1] = lines[idx] or ""
  end
  out[#out + 1] = last:sub(1, math.min(rel_end_col, #last))
  return table.concat(out, "\n")
end

local function get_math_symbol_span_at_pos(track, row, col)
  if not cursor_in_range(track, row, col, { include_right_edge = false }) then
    return nil
  end

  local ok_parser, parser = pcall(vim.treesitter.get_parser, track.bufnr, "typst")
  if not ok_parser or parser == nil then
    return nil
  end

  local trees = parser:parse()
  local tree = trees and trees[1] or nil
  if tree == nil then
    return nil
  end

  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col + 1)
  if node == nil then
    return nil
  end

  local formula_node = nil
  local target = node
  while target ~= nil do
    if target:type() == "formula" then
      formula_node = target
      break
    end
    target = target:parent()
  end
  if formula_node == nil then
    return nil
  end

  target = node
  while target ~= nil do
    local parent = target:parent()
    if parent == nil then
      return nil
    end
    if parent:id() == formula_node:id() then
      break
    end
    target = parent
  end

  local sr, sc, er, ec = target:range()
  if not cursor_in_range(track, sr, sc, { include_right_edge = false }) then
    return nil
  end
  if er < sr or (er == sr and ec < sc) then
    return nil
  end

  local text = track_source_slice(track, sr, sc, er, ec)
  if text == nil or text == "" or text:match("^%s+$") then
    return nil
  end

  return {
    start_row = sr,
    start_col = sc,
    end_row = er,
    end_col = ec,
  }
end

local function get_math_symbol_span_at_cursor(track, row, col, mode)
  if track == nil or track.node_type ~= "math" then
    return nil
  end

  local candidates = {}
  if cursor_in_range(track, row, col, { include_right_edge = false }) then
    candidates[#candidates + 1] = col
  end
  if is_insert_like_mode(mode) and col > 0 then
    local left_col = col - 1
    if cursor_in_range(track, row, left_col, { include_right_edge = false }) then
      candidates[#candidates + 1] = left_col
    end
  end

  for _, candidate_col in ipairs(candidates) do
    local span = get_math_symbol_span_at_pos(track, row, candidate_col)
    if span ~= nil then
      return span
    end
  end
  return nil
end

local function make_highlighted_preview_source(track, cursor_row, cursor_col, mode)
  if track == nil or track.node_type ~= "math" then
    return nil, nil, nil
  end

  local source_text = track.source or ""
  if source_text == "" then
    return nil, nil, nil
  end

  local source_kind = track.source_kind or (track.source_facts and track.source_facts.source_kind) or track.kind
  if source_kind ~= nil and source_kind ~= "typst" then
    return source_text, source_text, nil
  end

  local span = get_math_symbol_span_at_cursor(track, cursor_row, cursor_col, mode)
  if span == nil then
    return source_text, source_text, nil
  end

  if not cursor_in_range(track, span.start_row, span.start_col, { include_right_edge = false }) then
    return source_text, source_text, nil
  end

  local prefix = track_source_slice(track, track.row, track.col, span.start_row, span.start_col)
  local highlighted = track_source_slice(track, span.start_row, span.start_col, span.end_row, span.end_col)
  local suffix = track_source_slice(track, span.end_row, span.end_col, track.end_row, track.end_col)
  if prefix == nil or highlighted == nil or suffix == nil then
    return source_text, source_text, nil
  end

  local replacement = "#text(red)[$" .. highlighted .. "$];"
  return prefix .. replacement .. suffix, source_text, span
end

local function preview_render_key(
  projection,
  track,
  ctx,
  source_text,
  preview_source,
  cursor_row,
  cursor_col,
  span,
  config
)
  local parts = {
    "live-preview-projection-v1",
    projection.key,
    tostring(track.rev or 0),
    track.source_hash or "",
    track.prelude_signature or "",
    ctx.context_id or "",
    tostring(ctx.context_rev or 0),
    tostring(state.render_ppi(config)),
    wrapper.render_size_key(config),
    tostring(cursor_row),
    tostring(cursor_col),
    source_text or "",
    preview_source or "",
  }
  if span == nil then
    parts[#parts + 1] = "plain"
  else
    parts[#parts + 1] = tostring(span.start_row)
    parts[#parts + 1] = tostring(span.start_col)
    parts[#parts + 1] = tostring(span.end_row)
    parts[#parts + 1] = tostring(span.end_col)
  end
  return vim.fn.sha256(table.concat(parts, "\0"))
end

local function preview_service_cache_key(projection, track, ctx, config)
  local parts = {
    "live-preview-service-v1",
    projection.key,
    track.prelude_signature or "",
    ctx.context_id or "",
    tostring(ctx.context_rev or 0),
    ctx.effective_root or "",
    tostring(state.render_ppi(config)),
    wrapper.render_size_key(config),
  }
  return "preview:" .. vim.fn.sha256(table.concat(parts, "\0"))
end

local function request_id(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.next_preview_request_id = (bs.next_preview_request_id or 0) + 1
  return ("preview:%d:%d"):format(bufnr, bs.next_preview_request_id)
end

local function cleanup_asset(asset)
  if asset ~= nil and asset.image_id ~= nil then
    terminal.delete(asset.image_id)
  end
end

local function clear_visible_preview(preview, bufnr)
  display.clear_preview(preview, bufnr)
  cleanup_asset(preview.visible_asset)
  preview.visible_asset = nil
  preview.render_key = nil
  preview.track_key = nil
  preview.source_range = nil
  preview.handoff_key = nil
end

local function replace_preview_asset(bufnr, preview, track, asset, opts)
  opts = opts or {}
  local old = preview.visible_asset
  local old_render_key = preview.render_key
  local old_track_key = preview.track_key
  local old_source_range = preview.source_range
  local old_handoff_key = preview.handoff_key

  preview.visible_asset = asset
  preview.render_key = opts.render_key
  preview.track_key = opts.track_key
  preview.source_range = opts.source_range
  preview.handoff_key = opts.handoff_key

  if not display.show_preview(bufnr, preview, track, asset) then
    preview.visible_asset = old
    preview.render_key = old_render_key
    preview.track_key = old_track_key
    preview.source_range = old_source_range
    preview.handoff_key = old_handoff_key
    cleanup_asset(asset)
    return false
  end

  cleanup_asset(old)
  return true
end

-- Keep the preview surface non-blank when the cursor reveals a rendered formula:
-- clone the projection's current asset into the preview window until the live
-- highlighted render is ready to replace it.
local function seed_continuity_preview(bufnr, preview, projection, track, preview_key)
  if projection == nil or projection.visible_asset == nil then
    if preview.visible_asset ~= nil and (projection == nil or preview.track_key ~= projection.key) then
      clear_visible_preview(preview, bufnr)
    end
    return false
  end
  if preview.visible_asset ~= nil and preview.track_key == projection.key then
    return true
  end

  local source_asset = projection.visible_asset
  local cols, rows = display.preview_cell_dimensions(source_asset.width_px, source_asset.height_px)
  local asset = {
    image_id = state.allocate_image_id(bufnr),
    path = source_asset.path,
    width_px = source_asset.width_px,
    height_px = source_asset.height_px,
    cols = cols,
    rows = rows,
    render_key = "handoff:" .. tostring(preview_key),
    source_render_key = source_asset.render_key,
  }

  if not terminal.upload(asset.path, asset.image_id, asset.cols, asset.rows) then
    cleanup_asset(asset)
    if preview.visible_asset ~= nil and preview.track_key ~= projection.key then
      clear_visible_preview(preview, bufnr)
    end
    return false
  end

  local replaced = replace_preview_asset(bufnr, preview, track, asset, {
    render_key = nil,
    handoff_key = preview_key,
    track_key = projection.key,
    source_range = range_object(track),
  })
  if not replaced and preview.visible_asset ~= nil and preview.track_key ~= projection.key then
    clear_visible_preview(preview, bufnr)
  end
  return replaced
end

local function close_timer(preview)
  if preview.timer ~= nil then
    preview.timer:stop()
    if not preview.timer:is_closing() then
      preview.timer:close()
    end
    preview.timer = nil
  end
end

local function close_idle_timer(preview)
  if preview.idle_timer ~= nil then
    preview.idle_timer:stop()
    if not preview.idle_timer:is_closing() then
      preview.idle_timer:close()
    end
    preview.idle_timer = nil
  end
end

local function preview_idle_timeout_ms()
  local image = require("math-conceal.image")
  local timeout = tonumber(image.config and image.config.preview_idle_timeout_ms)
  if timeout == nil then
    timeout = 5000
  end
  return timeout
end

local function schedule_idle_stop(bufnr, preview)
  local timeout = preview_idle_timeout_ms()
  if timeout < 0 then
    close_idle_timer(preview)
    return
  end
  close_idle_timer(preview)
  preview.idle_timer = vim.uv.new_timer()
  preview.idle_timer:start(
    math.max(0, timeout),
    0,
    vim.schedule_wrap(function()
      close_idle_timer(preview)
      session.stop(bufnr, "preview")
    end)
  )
end

local function cancel_idle_stop(preview)
  close_idle_timer(preview)
end

function M.clear(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  if preview == nil then
    return
  end

  if opts.keep_timer ~= true then
    close_timer(preview)
  end
  session.cancel_live_preview(bufnr)
  clear_visible_preview(preview, bufnr)
  preview.pending_key = nil
  if opts.skip_idle_stop == true then
    close_idle_timer(preview)
  else
    schedule_idle_stop(bufnr, preview)
  end
end

local function render_projection_preview(bufnr, projection, track, cursor_row, cursor_col, mode)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil then
    M.clear(bufnr)
    return
  end

  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  cancel_idle_stop(preview)
  local attempted_continuity = false
  if preview.visible_asset == nil or preview.track_key ~= projection.key then
    attempted_continuity = true
    seed_continuity_preview(bufnr, preview, projection, track, nil)
  end

  local preview_source, source_text, span = make_highlighted_preview_source(track, cursor_row, cursor_col, mode)
  if preview_source == nil or source_text == nil then
    M.clear(bufnr)
    return
  end

  local ctx = context.resolve(bufnr, binding, tracker.get_context(bufnr), image.config)
  local key =
    preview_render_key(projection, track, ctx, source_text, preview_source, cursor_row, cursor_col, span, image.config)

  if preview.render_key == key and preview.visible_asset ~= nil then
    display.show_preview(bufnr, preview, track, preview.visible_asset)
    return
  end
  if preview.pending_key == key then
    if preview.visible_asset ~= nil and preview.track_key == projection.key then
      display.show_preview(bufnr, preview, track, preview.visible_asset)
    else
      seed_continuity_preview(bufnr, preview, projection, track, key)
    end
    return
  end

  local has_current_preview = preview.visible_asset ~= nil and preview.track_key == projection.key
  if not has_current_preview and not attempted_continuity then
    seed_continuity_preview(bufnr, preview, projection, track, key)
  end

  local preview_track = vim.deepcopy(track)
  preview_track.source = preview_source
  preview_track.source_hash = vim.fn.sha256(preview_source)
  preview_track.source_rows = math.max(1, wrapper.count_lines(preview_source))

  local slot_source, line_map = wrapper.build_slot_document(preview_track, ctx, image.config)
  local node_id = "preview:" .. projection.key
  local req_id = request_id(bufnr)
  local payload = {
    type = "render_formulas",
    backend = ctx.backend or "typst",
    request_id = req_id,
    cache_key = preview_service_cache_key(projection, track, ctx, image.config),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    output_dir = ctx.workspace.outputs_dir,
    ppi = state.render_ppi(image.config),
    worker_count = 1,
    nodes = {
      {
        node_id = node_id,
        node_rev = track.rev or 0,
        source_hash = vim.fn.sha256(slot_source),
        kind = track.node_type or "math",
        source = slot_source,
      },
    },
  }

  preview.pending_key = key
  preview.track_key = projection.key
  preview.source_range = range_object(track)

  local ok = session.render_formulas(bufnr, binding, payload, {
    kind = "live_preview",
    request_id = req_id,
    preview_key = key,
    track_key = projection.key,
    track_rev = track.rev or 0,
    node_id = node_id,
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    line_map = line_map,
    source_range = range_object(track),
    expected = 1,
  })

  if not ok then
    preview.pending_key = nil
    if preview.visible_asset == nil then
      M.clear(bufnr)
    end
  elseif preview.visible_asset ~= nil and preview.track_key == projection.key then
    display.show_preview(bufnr, preview, track, preview.visible_asset)
  end
end

function M.sync(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return
  end

  local image = require("math-conceal.image")
  if
    image.get_binding(bufnr) == nil
    or not image.is_render_allowed(bufnr)
    or image.config.live_preview_enabled == false
    or is_presentation_mode(bufnr)
  then
    M.clear(bufnr)
    return
  end

  local mode = vim.api.nvim_get_mode().mode or ""
  local winid = active_window_for_bufnr(bufnr)
  if winid == nil then
    M.clear(bufnr)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local tracks_by_key = track_view.by_key(bufnr, { require_valid = true })
  local projection, track = projection_at_cursor(bufnr, cursor_row, cursor_col, mode, tracks_by_key)
  if projection ~= nil then
    render_projection_preview(bufnr, projection, track, cursor_row, cursor_col, mode)
    return
  end

  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  if preview.visible_asset ~= nil and preview.track_key ~= nil then
    local preview_projection = bs.projections and bs.projections[preview.track_key] or nil
    local preview_track = track_view.for_projection(preview_projection, {
      by_key = tracks_by_key,
      require_valid = true,
    })
    if preview_track ~= nil and cursor_near_range(range_object(preview_track), cursor_row, cursor_col) then
      return
    end
  end
  M.clear(bufnr)
end

function M.schedule(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return
  end

  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  if preview.timer == nil or preview.timer:is_closing() then
    preview.timer = vim.uv.new_timer()
  end

  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  local delay = opts.immediate == true and 0 or math.max(0, tonumber(binding and binding.live_debounce) or 0)
  preview.timer:stop()
  preview.timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      if valid_loaded_buffer(bufnr) then
        M.sync(bufnr)
      end
    end)
  )
end

function M.refresh(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  if preview == nil or preview.visible_asset == nil or preview.track_key == nil then
    return
  end

  local projection = bs.projections and bs.projections[preview.track_key] or nil
  local track = track_view.for_projection(projection, { require_valid = true })
  if track == nil then
    M.clear(bufnr)
    return
  end
  display.show_preview(bufnr, preview, track, preview.visible_asset)
end

function M.handle_service_response(bufnr, resp, meta)
  if type(resp) ~= "table" or resp.type ~= "formula_rendered" or meta == nil then
    return
  end

  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  if
    preview == nil
    or preview.pending_key ~= meta.preview_key
    or resp.node_id ~= meta.node_id
    or tostring(resp.context_id or "") ~= tostring(meta.context_id or "")
    or tonumber(resp.context_rev or -1) ~= tonumber(meta.context_rev or -2)
    or tonumber(resp.node_rev or -1) ~= tonumber(meta.track_rev or -2)
  then
    return
  end

  preview.pending_key = nil
  local projection = bs.projections and bs.projections[meta.track_key] or nil
  local track = track_view.for_projection(projection, { require_valid = true })
  if track == nil or tonumber(track.rev or -1) ~= tonumber(meta.track_rev or -2) then
    if preview.visible_asset == nil then
      M.clear(bufnr)
    end
    return
  end

  if resp.status ~= "ok" or type(resp.path) ~= "string" or resp.path == "" then
    if preview.visible_asset == nil then
      M.clear(bufnr)
    end
    return
  end

  local cols, rows = display.preview_cell_dimensions(resp.width_px, resp.height_px)
  local asset = {
    image_id = state.allocate_image_id(bufnr),
    path = resp.path,
    width_px = resp.width_px,
    height_px = resp.height_px,
    cols = cols,
    rows = rows,
    render_key = meta.preview_key,
  }

  if not terminal.upload(asset.path, asset.image_id, asset.cols, asset.rows) then
    cleanup_asset(asset)
    if preview.visible_asset == nil then
      M.clear(bufnr)
    end
    return
  end

  replace_preview_asset(bufnr, preview, track, asset, {
    render_key = meta.preview_key,
    handoff_key = nil,
    track_key = meta.track_key,
    source_range = meta.source_range,
  })
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  if bs.live_preview ~= nil then
    close_timer(bs.live_preview)
    close_idle_timer(bs.live_preview)
  end
  M.clear(bufnr, { skip_idle_stop = true })
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.preview_ns, 0, -1)
  end
end

return M
