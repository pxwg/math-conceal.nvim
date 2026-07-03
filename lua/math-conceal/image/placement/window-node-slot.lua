local display = require("math-conceal.image.display")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")
local tracker = require("math-conceal.image.tracker")

local M = {}

local SLOT_PRIORITY = 230
local CONCEAL_PRIORITY = 225
local REDRAW_NS = vim.api.nvim_create_namespace("math-conceal.image.placement.window-node-slot.redraw")

local intents_by_buf = {}
local surfaces_by_win = {}
local augroup_id = nil
local provider_attached = false
local capability = nil

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function valid_buf(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function source_line(bufnr, row)
  local ok, line = pcall(tracker.source_line, bufnr, row)
  if ok and type(line) == "string" then
    return line
  end
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
end

local function source_prefix_display_width(bufnr, row, col)
  if row == nil or col == nil or col <= 0 or not valid_buf(bufnr) then
    return 0
  end
  local line = source_line(bufnr, row)
  return math.max(0, vim.fn.strdisplaywidth(line:sub(1, col)))
end

local function window_text_width(winid)
  local info = vim.fn.getwininfo(winid)[1] or {}
  local textoff = tonumber(info.textoff) or 0
  return math.max(1, vim.api.nvim_win_get_width(winid) - textoff)
end

local function window_view_signature(surface)
  if surface == nil or not valid_win(surface.win) or not valid_buf(surface.bufnr) then
    return nil
  end
  local ok, signature = pcall(vim.api.nvim_win_call, surface.win, function()
    if vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr then
      return nil
    end
    local info = vim.fn.getwininfo(surface.win)[1] or {}
    local view = vim.fn.winsaveview()
    local top = math.max(0, (tonumber(vim.fn.line("w0")) or 1) - 1)
    local bot = math.max(top, (tonumber(vim.fn.line("w$")) or top + 1) - 1)
    return table.concat({
      tostring(top),
      tostring(bot),
      tostring(view.topfill or 0),
      tostring(view.leftcol or 0),
      tostring(view.skipcol or 0),
      tostring(vim.api.nvim_win_get_width(surface.win)),
      tostring(vim.api.nvim_win_get_height(surface.win)),
      tostring(tonumber(info.textoff) or 0),
      tostring(vim.wo[surface.win].wrap and 1 or 0),
      tostring(vim.wo[surface.win].linebreak and 1 or 0),
      tostring(vim.wo[surface.win].breakindent and 1 or 0),
      tostring(vim.wo[surface.win].showbreak or ""),
      tostring(vim.wo[surface.win].number and 1 or 0),
      tostring(vim.wo[surface.win].relativenumber and 1 or 0),
      tostring(vim.wo[surface.win].signcolumn or ""),
    }, "|")
  end)
  if not ok then
    return nil
  end
  return signature
end

local function active_windows_for_buf(bufnr)
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if valid_win(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      wins[#wins + 1] = winid
    end
  end
  return wins
end

local function current_viewport(surface)
  if surface == nil or not valid_win(surface.win) then
    return nil, nil
  end

  local top, bot
  local ok = pcall(function()
    vim.api.nvim_win_call(surface.win, function()
      top = math.max(0, (tonumber(vim.fn.line("w0")) or 1) - 1)
      bot = math.max(top, (tonumber(vim.fn.line("w$")) or top + 1) - 1)
    end)
  end)
  if not ok then
    return nil, nil
  end
  return top, bot
end

local function delete_extmark(bufnr, ns, id)
  if id ~= nil and valid_buf(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
  end
end

local function clear_placement_extmarks(surface, placement)
  if surface == nil or placement == nil then
    return
  end
  for _, id in ipairs(placement.extmark_ids or {}) do
    delete_extmark(surface.bufnr, surface.ns, id)
  end
  placement.extmark_ids = {}
end

local function clear_slot_namespace_range(surface, view)
  if surface == nil or view == nil or not valid_buf(surface.bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, surface.bufnr, surface.ns, view.row, view.end_row + 1)
end

local function placement_extmarks_valid(surface, placement)
  if surface == nil or placement == nil or not valid_buf(surface.bufnr) then
    return false
  end
  local ids = placement.extmark_ids or {}
  if #ids == 0 then
    return false
  end
  for _, id in ipairs(ids) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(surface.bufnr, surface.ns, id, { details = true })
    local details = mark[3] or {}
    if mark[1] == nil or details.invalid == true then
      return false
    end
  end
  return true
end

local function redraw_surface_range(surface, start_row, end_row)
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

local function release_terminal_placement(placement)
  if placement == nil or placement.placement_id == nil then
    return
  end
  terminal.delete_placement(placement.image_id, placement.placement_id)
  placement.placement_id = nil
end

local function deactivate_placement(surface, placement, opts)
  if placement == nil then
    return
  end
  opts = opts or {}
  local had_extmarks = #(placement.extmark_ids or {}) > 0
  local source_start_row = placement.source_start_row
  local source_end_row = placement.source_end_row
  clear_placement_extmarks(surface, placement)
  if opts.keep_terminal_placement ~= true then
    release_terminal_placement(placement)
  end
  placement.placed = false
  if had_extmarks and source_start_row ~= nil and source_end_row ~= nil then
    redraw_surface_range(surface, source_start_row, source_end_row)
  end
end

local function close_window_placement(surface, key)
  if surface == nil or surface.placements == nil then
    return
  end
  local placement = surface.placements[key]
  if placement == nil then
    return
  end
  deactivate_placement(surface, placement)
  surface.placements[key] = nil
end

local function close_surface(surface)
  if surface == nil or surface.closed then
    return
  end
  surface.closed = true
  for key in pairs(vim.deepcopy(surface.placements or {})) do
    close_window_placement(surface, key)
  end
  if valid_buf(surface.bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, surface.bufnr, surface.ns, 0, -1)
  end
  if surfaces_by_win[surface.win] == surface then
    surfaces_by_win[surface.win] = nil
  end
end

function M.available()
  if capability ~= nil then
    return capability
  end
  if type(vim.api.nvim__ns_set) ~= "function" then
    capability = false
    return capability
  end
  local winid = vim.api.nvim_get_current_win()
  if not valid_win(winid) then
    capability = false
    return capability
  end
  local ns = vim.api.nvim_create_namespace("math-conceal.image.placement.window-node-slot.capability")
  capability = pcall(vim.api.nvim__ns_set, ns, { wins = { winid } })
  return capability
end

local function ensure_surface(winid, bufnr)
  if not M.available() or not valid_win(winid) or not valid_buf(bufnr) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end

  local surface = surfaces_by_win[winid]
  if surface ~= nil and surface.bufnr ~= bufnr then
    close_surface(surface)
    surface = nil
  end
  if surface ~= nil and not surface.closed then
    return surface
  end

  -- PERF: this intentionally uses one scoped namespace per window+buffer
  -- surface. Reusing namespaces can be revisited only if profiling shows
  -- namespace allocation pressure.
  local ns = vim.api.nvim_create_namespace(
    "math-conceal.image.placement.window-node-slot." .. tostring(bufnr) .. "." .. tostring(winid)
  )
  local ok = pcall(vim.api.nvim__ns_set, ns, { wins = { winid } })
  if not ok then
    return nil
  end

  surface = {
    win = winid,
    bufnr = bufnr,
    ns = ns,
    placements = {},
    closed = false,
  }
  surfaces_by_win[winid] = surface
  return surface
end

local function buf_intents(bufnr)
  bufnr = normalize_bufnr(bufnr)
  intents_by_buf[bufnr] = intents_by_buf[bufnr] or {}
  return intents_by_buf[bufnr]
end

local function normalize_intent(bufnr, intent)
  local asset = intent and intent.asset or nil
  if
    intent == nil
    or intent.key == nil
    or intent.ref == nil
    or asset == nil
    or asset.image_id == nil
    or intent.display_role ~= "block"
    or intent.block_role ~= "isolated"
  then
    return nil
  end

  local cols = math.max(1, math.floor(tonumber(asset.cols) or 1))
  local rows = math.max(1, math.floor(tonumber(asset.rows) or 1))
  return {
    key = intent.key,
    ref = vim.deepcopy(intent.ref),
    asset = vim.deepcopy(asset),
    cols = cols,
    rows = rows,
    render_key = asset.render_key,
    align = intent.align == "center" and "center" or "source",
    conceal_in_normal = intent.conceal_in_normal == true,
  }
end

local function conceal_source_cols(view, row)
  if row == nil or view == nil or row < view.row or row > view.end_row then
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

local function cursor_collides(surface, view)
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, surface.win)
  if not ok or cursor == nil then
    return false
  end
  local row, col = cursor[1] - 1, cursor[2]
  local start_col, end_col = conceal_source_cols(view, row)
  return start_col ~= nil and col >= start_col and col < end_col
end

local function selection_for_current_window(surface)
  if vim.api.nvim_get_current_win() ~= surface.win then
    return nil
  end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(surface.win)
  local mark = vim.fn.getpos("v")
  local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
  local mark_row, mark_col = mark[2] - 1, math.max(0, mark[3] - 1)
  if mode == "V" then
    return {
      mode = "line",
      start_row = math.min(mark_row, cursor_row),
      end_row = math.max(mark_row, cursor_row),
    }
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

local function selection_cols_for_row(selection, row)
  if selection == nil or row < selection.start_row or row > selection.end_row then
    return nil, nil
  end
  if selection.mode == "line" then
    return 0, math.huge
  end
  if selection.mode == "block" then
    return selection.start_col, selection.end_col
  end
  if selection.start_row == selection.end_row then
    return selection.start_col, selection.end_col
  end
  if row == selection.start_row then
    return selection.start_col, math.huge
  end
  if row == selection.end_row then
    return 0, selection.end_col
  end
  return 0, math.huge
end

local function ranges_overlap(a_start, a_end, b_start, b_end)
  return a_start < b_end and b_start < a_end
end

local function selection_collides(surface, view)
  local selection = selection_for_current_window(surface)
  if selection == nil then
    return false
  end

  local start_row = math.max(selection.start_row, view.row)
  local end_row = math.min(selection.end_row, view.end_row)
  if start_row > end_row then
    return false
  end

  for row = start_row, end_row do
    local selection_start_col, selection_end_col = selection_cols_for_row(selection, row)
    local node_start_col, node_end_col = conceal_source_cols(view, row)
    if
      selection_start_col ~= nil
      and node_start_col ~= nil
      and ranges_overlap(selection_start_col, selection_end_col, node_start_col, node_end_col)
    then
      return true
    end
  end
  return false
end

local function source_revealed_in_window(surface, placement, view)
  if selection_collides(surface, view) then
    return true
  end

  local mode = vim.api.nvim_get_mode().mode or ""
  if placement.conceal_in_normal == true and mode == "n" then
    return false
  end
  return cursor_collides(surface, view)
end

local function choose_carrier_count(raw_heights, image_rows)
  image_rows = math.max(1, math.floor(tonumber(image_rows) or 1))
  local carrier_count = 0
  local carrier_height = 0
  for _, raw in ipairs(raw_heights or {}) do
    raw = math.max(1, math.floor(tonumber(raw) or 1))
    if carrier_count == 0 then
      carrier_count = 1
      carrier_height = raw
      if carrier_height >= image_rows then
        break
      end
    elseif carrier_height + raw <= image_rows then
      carrier_count = carrier_count + 1
      carrier_height = carrier_height + raw
    else
      break
    end
  end
  return carrier_count, carrier_height, math.max(0, image_rows - carrier_height)
end

local function clear_measurement_artifacts(surface, placement, view)
  clear_placement_extmarks(surface, placement)
  clear_slot_namespace_range(surface, view)
  placement.extmark_ids = {}
end

local function build_layout(surface, placement, view)
  if view == nil or view.row == nil or view.end_row == nil or view.end_row < view.row then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(surface.bufnr)
  if view.row < 0 or view.end_row >= line_count then
    return nil
  end

  local text_width = window_text_width(surface.win)
  local measured = track_view.measure_source_layout(view, surface.win, { require_valid = true })
  if measured == nil then
    return nil
  end

  local raw_heights = {}
  for _, row_layout in ipairs(measured.rows or {}) do
    raw_heights[#raw_heights + 1] = row_layout.screen_height
  end
  local carrier_count, carrier_height, tail_count = choose_carrier_count(raw_heights, placement.rows)
  if carrier_count == 0 then
    return nil
  end

  local carrier_rows = {}
  for index = 1, carrier_count do
    local row_layout = measured.rows[index]
    carrier_rows[#carrier_rows + 1] = {
      row = row_layout.row,
      raw_height = raw_heights[index],
      segments = row_layout.segments or {},
    }
  end
  local source_prefix_cols = source_prefix_display_width(surface.bufnr, view.row, view.col)
  local prefix_cols = source_prefix_cols
  if placement.align == "center" and placement.cols < text_width then
    prefix_cols = math.floor((text_width - placement.cols) / 2)
  end

  return {
    source_start_row = view.row,
    source_end_row = view.end_row,
    prefix_cols = prefix_cols,
    source_prefix_cols = source_prefix_cols,
    carrier_rows = carrier_rows,
    carrier_height = carrier_height,
    tail_count = tail_count,
    collapsed_start_row = view.row + carrier_count,
    raw_heights = raw_heights,
  }
end

local function prefixed_line(line, prefix_cols)
  prefix_cols = math.max(0, math.floor(tonumber(prefix_cols) or 0))
  if prefix_cols == 0 then
    return line
  end
  local out = { { string.rep(" ", prefix_cols), "" } }
  for _, chunk in ipairs(line) do
    out[#out + 1] = chunk
  end
  return out
end

local function placeholder_line(placement, image_row)
  return {
    { display.placeholder_row(image_row, placement.cols), placement.hl },
  }
end

local function add_extmark(surface, row, col, opts)
  local id = vim.api.nvim_buf_set_extmark(surface.bufnr, surface.ns, row, col, opts)
  return id
end

local function render_conceal_for_row(surface, placement, view, row, ids)
  local start_col, end_col = conceal_source_cols(view, row)
  if start_col == nil then
    return
  end
  if end_col == math.huge then
    end_col = line_len(surface.bufnr, row)
  end
  if end_col < start_col then
    end_col = start_col
  end
  ids[#ids + 1] = add_extmark(surface, row, start_col, {
    end_row = row,
    end_col = end_col,
    conceal = "",
    invalidate = true,
    priority = CONCEAL_PRIORITY,
    strict = false,
  })
end

local function render_collapsed_tail(surface, layout, ids)
  if layout.collapsed_start_row > layout.source_end_row then
    return
  end
  ids[#ids + 1] = add_extmark(surface, layout.collapsed_start_row, 0, {
    end_row = layout.source_end_row,
    conceal_lines = "",
    invalidate = true,
    priority = CONCEAL_PRIORITY,
  })
end

local function render_carrier_overlays(surface, placement, layout, ids)
  local image_row = 1
  for _, carrier in ipairs(layout.carrier_rows) do
    for index = 1, carrier.raw_height do
      if image_row <= placement.rows then
        local segment = carrier.segments and carrier.segments[index] or nil
        local byte_col = segment and segment.byte_col or 0
        ids[#ids + 1] = add_extmark(surface, carrier.row, byte_col, {
          virt_text = placeholder_line(placement, image_row),
          virt_text_pos = "overlay",
          virt_text_win_col = layout.prefix_cols,
          virt_text_hide = false,
          invalidate = true,
          priority = SLOT_PRIORITY,
          strict = false,
        })
      end
      image_row = image_row + 1
    end
  end
end

local function render_tail_virt_lines(surface, placement, layout, ids)
  if layout.tail_count <= 0 then
    return
  end
  local last = layout.carrier_rows[#layout.carrier_rows]
  if last == nil then
    return
  end

  local lines = {}
  local first_tail_row = layout.carrier_height + 1
  for image_row = first_tail_row, placement.rows do
    lines[#lines + 1] = prefixed_line(placeholder_line(placement, image_row), layout.prefix_cols)
  end
  if #lines == 0 then
    return
  end

  ids[#ids + 1] = add_extmark(surface, last.row, 0, {
    virt_lines = lines,
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = SLOT_PRIORITY,
  })
end

local function layout_signature(placement, layout, revealed)
  if revealed then
    return table.concat({ "revealed", tostring(placement.image_id), tostring(placement.render_key or "") }, ":")
  end
  if layout == nil then
    return "invalid"
  end
  local parts = {
    tostring(placement.image_id),
    tostring(placement.render_key or ""),
    tostring(placement.align or "source"),
    tostring(placement.cols),
    tostring(placement.rows),
    tostring(layout.source_start_row),
    tostring(layout.source_end_row),
    tostring(layout.prefix_cols),
    tostring(layout.carrier_height),
    tostring(layout.tail_count),
  }
  for _, carrier in ipairs(layout.carrier_rows or {}) do
    parts[#parts + 1] = tostring(carrier.row) .. "@" .. tostring(carrier.raw_height)
    for _, segment in ipairs(carrier.segments or {}) do
      parts[#parts + 1] = table.concat({
        tostring(segment.start_vcol or 0),
        tostring(segment.end_vcol or 0),
        tostring(segment.byte_col or 0),
      }, ",")
    end
  end
  return table.concat(parts, "|")
end

local function ensure_terminal_placement(placement)
  if placement.placement_id == nil then
    placement.placement_id = state.allocate_placement_id(placement.bufnr)
  end
  if
    placement.image_uploaded ~= true
    and type(placement.path) == "string"
    and placement.path ~= ""
    and type(terminal.send_image) == "function"
  then
    if not terminal.send_image(placement.path, placement.image_id) then
      return false
    end
    placement.image_uploaded = true
  end
  return terminal.place_image(placement.image_id, placement.placement_id, placement.cols, placement.rows, { C = 1 })
end

local function update_placement_from_intent(surface, intent)
  local placement = surface.placements[intent.key]
  local image_changed = false
  local old_image_id = placement and placement.image_id or nil
  if placement == nil then
    placement = {
      bufnr = surface.bufnr,
      key = intent.key,
      extmark_ids = {},
    }
    surface.placements[intent.key] = placement
  elseif placement.image_id ~= nil and placement.image_id ~= intent.asset.image_id then
    image_changed = true
    deactivate_placement(surface, placement)
  end

  local layout_input_changed = placement.rows ~= nil
    and (
      placement.cols ~= intent.cols
      or placement.rows ~= intent.rows
      or placement.render_key ~= intent.render_key
      or placement.align ~= (intent.align or "source")
    )
  if placement.has_collapsed_tail == true and layout_input_changed then
    placement.clear_before_measure = true
  end
  placement.intent_changed = image_changed or layout_input_changed

  placement.ref = vim.deepcopy(intent.ref)
  placement.image_id = intent.asset.image_id
  placement.path = intent.asset.path
  placement.image_uploaded = intent.asset.uploaded == true
    or (old_image_id == intent.asset.image_id and placement.image_uploaded == true)
  placement.cols = intent.cols
  placement.rows = intent.rows
  placement.render_key = intent.render_key
  placement.align = intent.align or "source"
  placement.conceal_in_normal = intent.conceal_in_normal == true
  return placement
end

local function materialize_placement(surface, placement, opts)
  opts = opts or {}
  if surface == nil or surface.closed or placement == nil then
    return false, false
  end
  if
    not valid_win(surface.win)
    or not valid_buf(surface.bufnr)
    or vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr
  then
    close_surface(surface)
    return false, false
  end

  local view = track_view.for_ref(placement.ref, { require_valid = true })
  if view == nil then
    if placement.signature == "invalid" and not placement.placed and #(placement.extmark_ids or {}) == 0 then
      return false, false
    end
    deactivate_placement(surface, placement)
    local before = placement.signature
    placement.signature = "invalid"
    return false, before ~= placement.signature
  end

  if source_revealed_in_window(surface, placement, view) then
    local before = placement.signature
    local signature = layout_signature(placement, nil, true)
    if before == signature and not placement.placed and #(placement.extmark_ids or {}) == 0 then
      return true, false
    end
    -- Source reveal is a visibility transition, not hard disposal. Keep the
    -- Kitty Unicode-placeholder virtual placement alive so restore can reuse
    -- the same placement id; `placed=false` does not imply release.
    deactivate_placement(surface, placement, { keep_terminal_placement = true })
    placement.signature = signature
    redraw_surface_range(surface, view.row, view.end_row)
    return true, before ~= placement.signature
  end

  if
    opts.clear_before_measure ~= true
    and placement.clear_before_measure ~= true
    and placement.intent_changed ~= true
    and placement.signature ~= nil
    and placement.placed == true
    and placement.source_start_row == view.row
    and placement.source_end_row == view.end_row
    and placement_extmarks_valid(surface, placement)
  then
    return true, false
  end

  if opts.clear_before_measure == true or placement.clear_before_measure == true then
    clear_measurement_artifacts(surface, placement, view)
    placement.clear_before_measure = false
  end

  local layout = build_layout(surface, placement, view)
  if layout == nil then
    if placement.signature == "invalid" and not placement.placed and #(placement.extmark_ids or {}) == 0 then
      return false, false
    end
    deactivate_placement(surface, placement)
    local before = placement.signature
    placement.signature = "invalid"
    return false, before ~= placement.signature
  end

  local signature = layout_signature(placement, layout, false)
  if placement.signature == signature and placement.placed and placement_extmarks_valid(surface, placement) then
    placement.source_start_row = layout.source_start_row
    placement.source_end_row = layout.source_end_row
    placement.carrier_rows = layout.carrier_rows
    placement.tail_count = layout.tail_count
    placement.carrier_height = layout.carrier_height
    placement.prefix_cols = layout.prefix_cols
    placement.source_prefix_cols = layout.source_prefix_cols
    placement.has_collapsed_tail = layout.collapsed_start_row <= layout.source_end_row
    return true, false
  end

  clear_placement_extmarks(surface, placement)
  clear_slot_namespace_range(surface, view)
  placement.extmark_ids = {}

  if placement.placement_id == nil then
    placement.placement_id = state.allocate_placement_id(placement.bufnr)
  end
  placement.hl = state.placement_hl_group(placement.image_id, placement.placement_id)

  local ids = {}
  for _, carrier in ipairs(layout.carrier_rows) do
    render_conceal_for_row(surface, placement, view, carrier.row, ids)
  end
  render_collapsed_tail(surface, layout, ids)
  render_carrier_overlays(surface, placement, layout, ids)
  render_tail_virt_lines(surface, placement, layout, ids)

  placement.extmark_ids = ids
  if not ensure_terminal_placement(placement) then
    deactivate_placement(surface, placement)
    placement.signature = "invalid"
    return false, false
  end
  surface.repaint_signature = window_view_signature(surface)

  redraw_surface_range(surface, layout.source_start_row, layout.source_end_row)

  placement.placed = true
  placement.source_start_row = layout.source_start_row
  placement.source_end_row = layout.source_end_row
  placement.carrier_rows = layout.carrier_rows
  placement.tail_count = layout.tail_count
  placement.carrier_height = layout.carrier_height
  placement.prefix_cols = layout.prefix_cols
  placement.source_prefix_cols = layout.source_prefix_cols
  placement.has_collapsed_tail = layout.collapsed_start_row <= layout.source_end_row

  local before = placement.signature
  placement.signature = signature
  return true, before ~= placement.signature
end

local function materialize_surface_key(surface, key, opts)
  local intent = intents_by_buf[surface.bufnr] and intents_by_buf[surface.bufnr][key] or nil
  if intent == nil then
    close_window_placement(surface, key)
    return false, false
  end
  local placement = update_placement_from_intent(surface, intent)
  return materialize_placement(surface, placement, opts)
end

local function materialize_buf_key(bufnr, key, opts)
  local ok_any = false
  local changed = false
  local wins = active_windows_for_buf(bufnr)
  if #wins == 0 then
    return true, false
  end
  for _, winid in ipairs(wins) do
    local surface = ensure_surface(winid, bufnr)
    if surface ~= nil then
      local ok, did_change = materialize_surface_key(surface, key, opts)
      ok_any = ok_any or ok
      changed = changed or did_change
    end
  end
  return ok_any, changed
end

local function placement_intersects_viewport(placement, top, bot)
  if top == nil or bot == nil then
    return true
  end
  local start_row = placement.source_start_row
  local end_row = placement.source_end_row
  if start_row == nil or end_row == nil then
    return true
  end
  top = math.max(0, top - 2)
  bot = bot + 2
  return end_row >= top and start_row <= bot
end

local function repaint_surface(surface, keys)
  if surface == nil or surface.closed then
    return
  end
  if
    not valid_win(surface.win)
    or not valid_buf(surface.bufnr)
    or vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr
  then
    close_surface(surface)
    return
  end

  local top, bot = current_viewport(surface)
  local function repaint(placement)
    if
      placement ~= nil
      and placement.placed == true
      and placement.placement_id ~= nil
      and placement_intersects_viewport(placement, top, bot)
    then
      terminal.place_image(placement.image_id, placement.placement_id, placement.cols, placement.rows, { C = 1 })
    end
  end

  local function run()
    if keys ~= nil then
      for key in pairs(keys) do
        repaint(surface.placements[key])
      end
      return
    end
    for _, placement in pairs(surface.placements or {}) do
      repaint(placement)
    end
  end

  if type(terminal.batch) == "function" then
    terminal.batch(run)
  else
    run()
  end
  surface.repaint_signature = window_view_signature(surface)
end

local function schedule_repaint(surface, key)
  if surface == nil or surface.closed then
    return
  end
  if key == nil then
    surface.repaint_full = true
    surface.repaint_keys = nil
  elseif not surface.repaint_full then
    surface.repaint_keys = surface.repaint_keys or {}
    surface.repaint_keys[key] = true
  end
  if surface.repaint_scheduled then
    return
  end
  surface.repaint_scheduled = true
  vim.schedule(function()
    surface.repaint_scheduled = false
    local keys = nil
    if not surface.repaint_full then
      keys = surface.repaint_keys
    end
    surface.repaint_full = false
    surface.repaint_keys = nil
    repaint_surface(surface, keys)
  end)
end

local function schedule_viewport_repaint(surface)
  if surface == nil or surface.closed then
    return
  end
  local signature = window_view_signature(surface)
  if signature == nil or surface.repaint_signature == signature then
    return
  end
  surface.repaint_signature = signature
  schedule_repaint(surface)
end

local function refresh_surface(surface, opts)
  if surface == nil or surface.closed then
    return false
  end
  local changed = false
  for key in pairs(intents_by_buf[surface.bufnr] or {}) do
    local _, did_change = materialize_surface_key(surface, key, opts)
    changed = changed or did_change
  end
  return changed
end

local function setup_decoration_provider()
  if provider_attached or type(vim.api.nvim_set_decoration_provider) ~= "function" then
    return
  end
  provider_attached = true
  vim.api.nvim_set_decoration_provider(REDRAW_NS, {
    on_win = function(_, winid, bufnr)
      local surface = surfaces_by_win[winid]
      if surface ~= nil and surface.bufnr == bufnr then
        schedule_viewport_repaint(surface)
      end
      return false
    end,
  })
end

function M.sync(bufnr, intent)
  bufnr = normalize_bufnr(bufnr)
  if not valid_buf(bufnr) then
    return false
  end
  local normalized = normalize_intent(bufnr, intent)
  if normalized == nil then
    if intent ~= nil and intent.key ~= nil then
      M.close_key(bufnr, intent.key)
    end
    return false
  end
  if not M.available() then
    return false
  end

  buf_intents(bufnr)[normalized.key] = normalized
  local ok_any = materialize_buf_key(bufnr, normalized.key)
  return ok_any
end

function M.close_key(bufnr, key)
  bufnr = normalize_bufnr(bufnr)
  if key == nil then
    return
  end
  local records = intents_by_buf[bufnr]
  if records ~= nil then
    records[key] = nil
  end
  for _, surface in pairs(surfaces_by_win) do
    if surface.bufnr == bufnr then
      close_window_placement(surface, key)
    end
  end
end

function M.close_all(bufnr)
  bufnr = normalize_bufnr(bufnr)
  intents_by_buf[bufnr] = nil
  local surfaces = {}
  for _, surface in pairs(surfaces_by_win) do
    if surface.bufnr == bufnr then
      surfaces[#surfaces + 1] = surface
    end
  end
  for _, surface in ipairs(surfaces) do
    close_surface(surface)
  end
end

function M.reconcile(bufnr, keep_keys)
  bufnr = normalize_bufnr(bufnr)
  keep_keys = keep_keys or {}
  local records = intents_by_buf[bufnr] or {}
  for key in pairs(vim.deepcopy(records)) do
    if keep_keys[key] ~= true then
      M.close_key(bufnr, key)
    end
  end
end

function M.refresh_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not valid_buf(bufnr) then
    return false
  end
  local changed = false
  for _, winid in ipairs(active_windows_for_buf(bufnr)) do
    local surface = ensure_surface(winid, bufnr)
    if surface ~= nil then
      changed = refresh_surface(surface, { clear_before_measure = true }) or changed
    end
  end
  return changed
end

function M.refresh_geometry(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  local records = intents_by_buf[bufnr] or {}
  local only_keys = opts.keys
  local changed = false
  for key in pairs(records) do
    if only_keys == nil or only_keys[key] == true then
      local _, did_change = materialize_buf_key(bufnr, key, opts)
      changed = changed or did_change
    end
  end
  return changed
end

function M.batch(fn)
  if type(fn) ~= "function" then
    return nil
  end
  return fn()
end

function M.refresh_all()
  local surfaces = {}
  for _, surface in pairs(surfaces_by_win) do
    surfaces[#surfaces + 1] = surface
  end
  for _, surface in ipairs(surfaces) do
    refresh_surface(surface, { clear_before_measure = true })
  end
end

function M.setup()
  if augroup_id ~= nil then
    return
  end
  augroup_id = vim.api.nvim_create_augroup("math-conceal.image.placement.window-node-slot", { clear = true })
  setup_decoration_provider()
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup_id,
    desc = "refresh math-conceal window node slot geometry",
    callback = function()
      M.refresh_all()
    end,
  })
  if not provider_attached then
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = augroup_id,
      desc = "repaint math-conceal window node slot placements",
      callback = function()
        for _, surface in pairs(surfaces_by_win) do
          schedule_viewport_repaint(surface)
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup_id,
    desc = "materialize math-conceal window node slots",
    callback = function(ev)
      M.refresh_buf(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = augroup_id,
    desc = "drop math-conceal window node slot surface",
    callback = function(ev)
      local winid = vim.api.nvim_get_current_win()
      local surface = surfaces_by_win[winid]
      if surface ~= nil and surface.bufnr == ev.buf then
        close_surface(surface)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup_id,
    desc = "close math-conceal window node slot surface",
    callback = function(ev)
      local winid = tonumber(ev.match)
      if winid ~= nil then
        close_surface(surfaces_by_win[winid])
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = augroup_id,
    desc = "clear math-conceal window node slot placements",
    callback = function(ev)
      M.close_all(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = augroup_id,
    pattern = { "wrap", "linebreak", "breakindent", "showbreak", "number", "relativenumber", "signcolumn" },
    desc = "remeasure math-conceal window node slots after window option changes",
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      refresh_surface(surfaces_by_win[winid], { clear_before_measure = true })
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup_id,
    desc = "refresh math-conceal window node slot highlights",
    callback = function()
      M.refresh_all()
    end,
  })
end

function M._state()
  return {
    available = M.available(),
    intents_by_buf = intents_by_buf,
    provider_attached = provider_attached,
    surfaces_by_win = surfaces_by_win,
  }
end

function M._choose_carrier_count(raw_heights, image_rows)
  return choose_carrier_count(raw_heights, image_rows)
end

return M
