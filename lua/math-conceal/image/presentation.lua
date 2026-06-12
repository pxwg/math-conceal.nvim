local cursor_visibility = require("math-conceal.image.cursor-visibility")
local state = require("math-conceal.image.state")

local M = {}
local cursor_guard = {}

local function item_display_bufnr(item)
  if item == nil then
    return nil
  end
  if item.render_target == "float" or item.render_target == "preview_float" then
    return item.target_bufnr or item.bufnr
  end
  return item.bufnr
end

local function extmark_range(bufnr, ns_id, extmark_id)
  if type(extmark_id) ~= "number" then
    return nil
  end

  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, { details = true })
  if not ok or mark == nil or #mark == 0 then
    return nil
  end

  local details = mark[3] or {}
  if details.invalid then
    return nil
  end

  return {
    start_row = mark[1],
    end_row = details.end_row or mark[1],
  }
end

local function add_range(ranges, start_row, end_row)
  if type(start_row) ~= "number" or type(end_row) ~= "number" then
    return
  end
  ranges[#ranges + 1] = {
    start_row = math.min(start_row, end_row),
    end_row = math.max(start_row, end_row),
  }
end

local function add_extmark_range(ranges, bufnr, ns_id, extmark_id)
  local range = extmark_range(bufnr, ns_id, extmark_id)
  if range ~= nil then
    add_range(ranges, range.start_row, range.end_row)
  end
end

local function collect_protected_ranges(bufnr)
  local ranges = {}
  local bs = state.get_buf_state(bufnr)

  for _, item in pairs(state.item_by_image_id or {}) do
    if
      item_display_bufnr(item) == bufnr
      and item.render_target ~= "float"
      and item.render_target ~= "preview_float"
    then
      local extmark_id = item.extmark_id
      if extmark_id == nil and item.image_id ~= nil then
        extmark_id = state.image_id_to_extmark[item.image_id]
      end
      add_extmark_range(ranges, bufnr, state.ns_id, extmark_id)
    end
  end

  for _, run in pairs(bs.line_run_marks or {}) do
    local start_row = nil
    local end_row = nil
    local function include_range(range)
      if range == nil then
        return
      end
      start_row = start_row == nil and range.start_row or math.min(start_row, range.start_row)
      end_row = end_row == nil and range.end_row or math.max(end_row, range.end_row)
    end

    for _, conceal_id in pairs(run.conceal_ids or {}) do
      include_range(extmark_range(bufnr, state.ns_id2, conceal_id))
    end
    for _, sub_id in pairs(run.sub_ids or {}) do
      include_range(extmark_range(bufnr, state.ns_id2, sub_id))
    end
    for extmark_id in pairs(run.extmark_ids or run.block_extmark_ids or {}) do
      include_range(extmark_range(bufnr, state.ns_id, extmark_id))
    end
    if start_row ~= nil and end_row ~= nil then
      add_range(ranges, start_row, end_row)
    end
  end

  return ranges
end

local function protected_range_at_row(ranges, row)
  local start_row = nil
  local end_row = nil
  local changed = true

  while changed do
    changed = false
    for _, range in ipairs(ranges) do
      if start_row == nil then
        if row >= range.start_row and row <= range.end_row then
          start_row = range.start_row
          end_row = range.end_row
          changed = true
        end
      elseif range.end_row >= start_row - 1 and range.start_row <= end_row + 1 then
        local next_start = math.min(start_row, range.start_row)
        local next_end = math.max(end_row, range.end_row)
        if next_start ~= start_row or next_end ~= end_row then
          start_row = next_start
          end_row = next_end
          changed = true
        end
      end
    end
  end

  if start_row == nil then
    return nil
  end
  return { start_row = start_row, end_row = end_row }
end

local function row_is_protected(ranges, row)
  return protected_range_at_row(ranges, row) ~= nil
end

local function nearest_unprotected_row(bufnr, range, direction, ranges)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return nil
  end

  local function scan(row, step)
    while row >= 0 and row < line_count do
      if not row_is_protected(ranges, row) then
        return row
      end
      row = row + step
    end
  end

  if direction < 0 then
    return scan(range.start_row - 1, -1) or scan(range.end_row + 1, 1)
  end
  return scan(range.end_row + 1, 1) or scan(range.start_row - 1, -1)
end

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function valid_buf_window(bufnr, winid)
  if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local ok, win_bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  return ok and win_bufnr == bufnr
end

local function target_windows(bufnr, opts)
  opts = opts or {}
  if opts.winid ~= nil then
    if valid_buf_window(bufnr, opts.winid) then
      return { opts.winid }
    end
    return {}
  end

  local wins = {}
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if valid_buf_window(bufnr, winid) then
      wins[#wins + 1] = winid
    end
  end
  return wins
end

local function keep_window_cursor_out_of_protected_range(bufnr, winid, ranges, opts)
  if cursor_guard[winid] then
    return false
  end

  local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if not ok_cursor or cursor == nil then
    return false
  end

  local row = cursor[1] - 1
  local protected = protected_range_at_row(ranges, row)
  local bs = state.get_buf_state(bufnr)
  bs.presentation_cursor_by_win = bs.presentation_cursor_by_win or {}
  local win_state = bs.presentation_cursor_by_win[winid] or {}
  bs.presentation_cursor_by_win[winid] = win_state

  if protected == nil then
    win_state.last_row = row
    win_state.last_col = cursor[2]
    return false
  end

  local last_row = win_state.last_row
  local direction = opts.direction
  if direction == nil then
    direction = last_row ~= nil and row < last_row and -1 or 1
  end

  local target_row = nearest_unprotected_row(bufnr, protected, direction, ranges)
  if target_row == nil then
    return false
  end

  local target_col = math.min(cursor[2], line_len(bufnr, target_row))
  cursor_guard[winid] = true
  local ok_set = pcall(vim.api.nvim_win_set_cursor, winid, { target_row + 1, target_col })
  cursor_guard[winid] = nil

  if ok_set then
    win_state.last_row = target_row
    win_state.last_col = target_col
    return true
  end
  return false
end

function M.keep_cursor_out_of_protected_range(bufnr, opts)
  opts = opts or {}
  if
    not cursor_visibility.is_presentation_mode(bufnr)
    or cursor_visibility.is_visual_mode()
    or not vim.api.nvim_buf_is_valid(bufnr)
  then
    return false
  end

  local wins = target_windows(bufnr, opts)
  if #wins == 0 then
    return false
  end

  local ranges = collect_protected_ranges(bufnr)
  local moved = false
  for _, winid in ipairs(wins) do
    moved = keep_window_cursor_out_of_protected_range(bufnr, winid, ranges, opts) or moved
  end
  return moved
end

return M
