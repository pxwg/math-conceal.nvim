--- Cursor/source visibility rules shared by full overlay placement and hover.
local M = {}

local function clamp_range_to_buffer(bufnr, range)
  if range == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return nil
  end

  local start_row = math.max(0, math.min(range[1], line_count - 1))
  local end_row = math.max(start_row, math.min(range[3], line_count - 1))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #lines == 0 then
    return nil
  end

  local start_col = math.max(0, math.min(range[2], #(lines[1] or "")))
  local end_col
  if start_row == end_row then
    end_col = math.max(start_col, math.min(range[4], #(lines[#lines] or "")))
  else
    end_col = math.max(0, math.min(range[4], #(lines[#lines] or "")))
  end

  return { start_row, start_col, end_row, end_col }
end

function M.is_insert_like_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode or ""
  return mode:find("i", 1, true) ~= nil or mode:find("R", 1, true) ~= nil
end

function M.is_visual_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode or ""
  return mode == "v" or mode == "V" or mode == "\22"
end

function M.presentation_keeps_conceal(bufnr, mode)
  return M.is_presentation_mode(bufnr) and not M.is_visual_mode(mode)
end

function M.cursor_in_range(range, row, col, opts)
  opts = opts or {}
  local sr, sc, er, ec = range[1], range[2], range[3], range[4]
  local include_right_edge = opts.include_right_edge == true

  if row < sr or row > er then
    return false
  end

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

function M.cursor_engages_inline_item(range, row, col, mode)
  return M.cursor_in_range(range, row, col, {
    include_right_edge = M.is_insert_like_mode(mode),
  })
end

function M.is_presentation_mode(bufnr)
  local ok, render = pcall(require, "math-conceal.render")
  if not ok or type(render.is_presentation_mode) ~= "function" then
    return false
  end

  local ok_mode, enabled = pcall(render.is_presentation_mode, bufnr)
  return ok_mode and enabled == true
end

local function byte_is_escaped(line, byte_idx)
  local slash_count = 0
  local i = byte_idx - 1
  while i >= 1 and line:sub(i, i) == "\\" do
    slash_count = slash_count + 1
    i = i - 1
  end
  return slash_count % 2 == 1
end

local function current_dollar_math_span(bufnr, row, anchor_col, cursor_col)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if type(line) ~= "string" then
    return nil
  end

  local delimiters = {}
  local byte_idx = 1
  while true do
    byte_idx = line:find("$", byte_idx, true)
    if byte_idx == nil then
      break
    end
    if not byte_is_escaped(line, byte_idx) then
      delimiters[#delimiters + 1] = byte_idx - 1
    end
    byte_idx = byte_idx + 1
  end

  for idx = 1, #delimiters - 1, 2 do
    local start_col = delimiters[idx]
    local end_col = delimiters[idx + 1] + 1
    if anchor_col >= start_col and anchor_col < end_col and cursor_col >= start_col and cursor_col <= end_col then
      return { row, start_col, row, end_col }
    end
  end

  return nil
end

function M.get_item_effective_range(item)
  if item == nil then
    return nil
  end
  return clamp_range_to_buffer(item.bufnr, item.range)
end

function M.should_unconceal_item_for_row(item, row, cursor_row, cursor_col, mode)
  if item ~= nil and M.presentation_keeps_conceal(item.bufnr, mode) then
    return false
  end

  local effective_range = M.get_item_effective_range(item)
  if effective_range == nil then
    return false
  end

  local sem = item.semantics or {}
  local source_kind = sem.source_kind or item.node_type
  local math_like = source_kind == "math" or source_kind == "latex"
  local sr, _, er, _ = effective_range[1], effective_range[2], effective_range[3], effective_range[4]
  local display_range = item.display_range ~= nil and clamp_range_to_buffer(item.bufnr, item.display_range) or nil

  if math_like and sem.display_kind == "block" and display_range ~= nil then
    return M.cursor_engages_inline_item(display_range, cursor_row, cursor_col, mode)
  end

  if sr == er and math_like then
    if row ~= cursor_row then
      return false
    end
    if M.is_insert_like_mode(mode) then
      local current_span = current_dollar_math_span(item.bufnr, cursor_row, effective_range[2], cursor_col)
      if current_span ~= nil and M.cursor_engages_inline_item(current_span, cursor_row, cursor_col, mode) then
        return true
      end
    end
    local trigger_range = effective_range
    if sem.render_whole_line and display_range ~= nil then
      trigger_range = display_range
    end
    return M.cursor_engages_inline_item(trigger_range, cursor_row, cursor_col, mode)
  end

  if source_kind == "code" and sr == er then
    if row ~= cursor_row then
      return false
    end
    return M.cursor_engages_inline_item(effective_range, cursor_row, cursor_col, mode)
  end

  if math_like or source_kind == "code" then
    return row >= sr and row <= er
  end

  return false
end

local function conceal_in_normal_mode(mode)
  if mode == nil or mode:find("n", 1, true) == nil then
    return false
  end
  local ok, main = pcall(require, "math-conceal.image")
  return ok and main.config and main.config.conceal_in_normal == true
end

function M.should_preserve_source_at_cursor(bufnr, item, mode)
  if item == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.api.nvim_get_current_buf() ~= bufnr then
    return false
  end

  mode = mode or vim.api.nvim_get_mode().mode or ""
  if M.presentation_keeps_conceal(bufnr, mode) then
    return false
  end
  if conceal_in_normal_mode(mode) then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  return M.should_unconceal_item_for_row(item, cursor_row, cursor_row, cursor_col, mode)
end

return M
