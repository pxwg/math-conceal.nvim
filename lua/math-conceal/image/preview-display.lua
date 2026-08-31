local grid = require("math-conceal.image.grid")
local state = require("math-conceal.image.state")

local M = {}

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function clamp_range(bufnr, start_row, start_col, end_row, end_col)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return 0, 0, 0, 0
  end

  start_row = math.max(0, math.min(start_row, line_count - 1))
  end_row = math.max(start_row, math.min(end_row, line_count - 1))
  start_col = math.max(0, math.min(start_col, line_len(bufnr, start_row)))
  end_col = math.max(0, math.min(end_col, line_len(bufnr, end_row)))
  if start_row == end_row and end_col < start_col then
    end_col = start_col
  end
  return start_row, start_col, end_row, end_col
end

local function display_range(track)
  if track.source_display_kind == "block" and track.render_whole_line == true then
    return clamp_range(track.bufnr, track.row, 0, track.end_row, line_len(track.bufnr, track.end_row))
  end
  return clamp_range(track.bufnr, track.row, track.col, track.end_row, track.end_col)
end

local function active_window_for_bufnr(bufnr)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current) and vim.api.nvim_win_get_buf(current) == bufnr then
    return current
  end

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end
  return nil
end

local function preview_left_pad_cols(bufnr, row, col)
  local winid = active_window_for_bufnr(bufnr)
  if winid == nil then
    local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false) or { "" })[1] or ""
    return vim.fn.strdisplaywidth(line:sub(1, col))
  end

  local sp = vim.fn.screenpos(winid, row + 1, col + 1)
  local winpos = vim.api.nvim_win_get_position(winid)
  local wininfo = vim.fn.getwininfo(winid)[1] or {}
  local textoff = wininfo.textoff or 0
  local screen_col = math.max(1, (sp.col or 1) - winpos[2] - textoff)
  return screen_col - 1
end

local function range_screen_rect(bufnr, start_row, start_col, end_row, end_col)
  local winid = active_window_for_bufnr(bufnr)
  if winid == nil then
    return nil
  end

  local start_sp = vim.fn.screenpos(winid, start_row + 1, start_col + 1)
  local end_sp = vim.fn.screenpos(winid, end_row + 1, math.max(start_col + 1, end_col))
  if start_sp == nil or end_sp == nil or (start_sp.row or 0) <= 0 or (end_sp.row or 0) <= 0 then
    return nil
  end

  return {
    top = math.max(0, (start_sp.row or 1) - 1),
    bottom = math.max(0, (end_sp.row or 1) - 1),
  }
end

local function choose_vertical(bufnr, preview, start_row, start_col, end_row, end_col, rows)
  local preferred = (preview and preview.vertical) or "above"
  local rect = range_screen_rect(bufnr, start_row, start_col, end_row, end_col)
  if rect == nil then
    return preferred
  end

  local editor_h = math.max(1, vim.o.lines - vim.o.cmdheight)
  local above_fits = rect.top - rows >= 0
  local below_fits = rect.bottom + rows + 1 <= editor_h
  if preferred == "above" and above_fits then
    return "above"
  end
  if preferred == "below" and below_fits then
    return "below"
  end
  if below_fits then
    return "below"
  end
  if above_fits then
    return "above"
  end
  return preferred
end

function M.preview_cell_dimensions(width_px, height_px)
  return grid.preview_dimensions(width_px, height_px)
end

function M.clear_preview(preview, bufnr)
  if preview == nil then
    return
  end
  bufnr = bufnr or preview.bufnr
  if preview.extmark_id ~= nil and bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.preview_ns, preview.extmark_id)
  end
  preview.extmark_id = nil
end

function M.show_preview(bufnr, preview, track, asset)
  if
    preview == nil
    or track == nil
    or asset == nil
    or asset.image_id == nil
    or not vim.api.nvim_buf_is_valid(bufnr)
  then
    return false
  end

  local start_row, start_col, end_row, end_col = display_range(track)
  local cols, rows = grid.clamp(asset.cols, asset.rows)
  asset.cols = cols
  asset.rows = rows
  local vertical = choose_vertical(bufnr, preview, start_row, start_col, end_row, end_col, rows)
  preview.vertical = vertical

  local pad = preview_left_pad_cols(bufnr, start_row, start_col)
  local pad_text = pad > 0 and string.rep(" ", pad) or ""
  local hl = state.image_hl_group(asset.image_id)
  local lines = {}
  for row = 1, rows do
    lines[#lines + 1] = { { pad_text, "" }, { grid.placeholder_row(row, cols), hl } }
  end

  local anchor_row = vertical == "above" and start_row or end_row
  preview.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.preview_ns, anchor_row, 0, {
    id = preview.extmark_id,
    invalidate = true,
    priority = 230,
    virt_lines = lines,
    virt_lines_above = vertical == "above",
  })
  return true
end

return M
