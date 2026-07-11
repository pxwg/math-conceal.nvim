local tracker = require("math-conceal.image.tracker")

local M = {}

local function is_blank(text)
  return (text or ""):match("^%s*$") ~= nil
end

local function source_line(view, row)
  local ok, line = pcall(tracker.source_line, view.bufnr, row)
  if ok and type(line) == "string" then
    return line
  end
  return vim.api.nvim_buf_get_lines(view.bufnr, row, row + 1, false)[1] or ""
end

function M.role(view, display_kind)
  if view == nil or display_kind ~= "block" then
    return nil
  end
  local start_line = source_line(view, view.row)
  local end_line = view.row == view.end_row and start_line or source_line(view, view.end_row)
  local prefix_blank = is_blank(start_line:sub(1, view.col))
  local suffix_blank = is_blank(end_line:sub(view.end_col + 1))

  if prefix_blank and suffix_blank then
    return "isolated"
  end
  if prefix_blank then
    return "suffix"
  end
  if suffix_blank then
    return "prefix"
  end
  if view.row == view.end_row then
    return "sandwich"
  end
  return "prefix"
end

return M
