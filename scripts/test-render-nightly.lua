-- Neovim 0.13 native and projected Unicode conceal, using the LaTeX parser.
-- nvim --headless -u NONE -l scripts/test-render-nightly.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local render = require("math-conceal.render")
if not render.uses_persistent_conceal() then
  print("render-nightly-skip: requires Neovim 0.13")
  return
end

local function attach(lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "tex"
  assert(render.attach(buf, "latex"))
  return buf
end

local function cursor(win, row, col)
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, { row, col })
  api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_win_get_buf(win) })
end

local function persistent()
  vim.o.columns, vim.o.lines = 80, 24
  render.setup({ conceal = {} }, "latex")
  render.update_query("latex", [[((generic_command) @symbol (#set! @symbol conceal "X"))]])

  local function marks(win)
    local ns = render.window_namespace(win)
    local buf = api.nvim_win_get_buf(win)
    return ns and api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}
  end
  local function marked_rows(win)
    local rows = {}
    for _, mark in ipairs(marks(win)) do
      rows[mark[2]] = mark[4].conceal
    end
    return rows
  end
  -- Async parsing and on_end coverage repaints settle over a few event-loop turns.
  local function settle()
    local last
    for _ = 1, 20 do
      vim.cmd("redraw")
      vim.wait(10)
      local info = vim.fn.getwininfo(api.nvim_get_current_win())[1]
      local now = info.topline .. ":" .. info.botline .. ":" .. #vim.tbl_keys(marked_rows(info.winid))
      if now == last then
        return
      end
      last = now
    end
  end
  local function height(win, row)
    return api.nvim_win_text_height(win, { start_row = row, end_row = row }).all
  end
  local function move(win, row, col)
    cursor(win, row, col)
    settle()
  end

  -- 38 symbols wrap as source; concealed they fit 80 columns, one revealed symbol does not.
  local long = string.rep("\\alpha ", 38)
  local lines = { "plain" }
  for _ = 2, 60 do
    lines[#lines + 1] = long
  end
  local buf = attach(lines)
  local left = api.nvim_get_current_win()
  api.nvim_win_set_buf(left, buf)
  vim.wo[left].wrap = true
  api.nvim_win_set_cursor(left, { 1, 0 })
  settle()

  assert(height(left, 1) == 1, "persistent conceal collapses wrapped rows: " .. height(left, 1))
  local info = vim.fn.getwininfo(left)[1]
  assert(info.botline - 1 >= 20, "reflow exposes more source rows: " .. info.botline)
  local rows = marked_rows(left)
  for row = info.topline - 1, info.botline - 1 do
    assert(row == 0 or rows[row] == "X", "row exposed by reflow is concealed: " .. row)
  end

  move(left, 2, 3)
  assert(height(left, 1) > 1, "cursor reveal restores source width")
  assert(height(left, 2) == 1, "neighbour rows stay concealed")
  local function row_count(win, row)
    return #vim.tbl_filter(function(mark)
      return mark[2] == row
    end, marks(win))
  end
  assert(row_count(left, 1) == 37, "only the symbol under the cursor expands")

  vim.cmd("vsplit")
  local right = api.nvim_get_current_win()
  move(right, 1, 0)
  move(left, 2, 3)
  assert(height(left, 1) > height(right, 1), "split windows keep independent reveal and layout")
  assert(render.window_namespace(left) ~= render.window_namespace(right), "each window owns a namespace")

  -- Edit: the replaced symbol gets a fresh mark, deleted text leaves none behind.
  move(left, 1, 0)
  api.nvim_buf_set_lines(buf, 2, 3, false, { "\\beta" })
  settle()
  assert(row_count(left, 2) == 1, "edited row has exactly one mark")
  api.nvim_buf_set_text(buf, 2, 0, 2, 5, { "" })
  settle()
  assert(marked_rows(left)[2] == nil, "deleted symbol leaves no stale conceal")
  assert(row_count(left, 1) == 38, "untouched rows keep every conceal after edits")

  -- Edits invalidate only the rows they touch: shifted rows keep their marks, and cursor reveal
  -- still flips them.
  move(left, 1, 0)
  api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted", "\\beta \\beta" })
  settle()
  assert(row_count(left, 1) == 2, "inserted symbols are concealed: " .. row_count(left, 1))
  assert(row_count(left, 3) == 38, "shifted rows keep exactly their marks: " .. row_count(left, 3))
  move(left, 4, 3)
  assert(row_count(left, 3) == 37, "cursor reveal flips a shifted row: " .. row_count(left, 3))
  move(left, 1, 0)
  assert(row_count(left, 3) == 38, "leaving a shifted row conceals it again: " .. row_count(left, 3))
  api.nvim_buf_set_text(buf, 3, 0, 3, 0, { "\\gamma " })
  settle()
  assert(row_count(left, 3) == 39, "typed symbol is concealed: " .. row_count(left, 3))
  api.nvim_buf_set_lines(buf, 0, 2, false, {})
  api.nvim_buf_set_text(buf, 1, 0, 1, 7, { "" })
  settle()
  assert(row_count(left, 1) == 38 and row_count(left, 0) == 0, "deleted rows leave no marks behind")
  local total = #marks(left)
  vim.cmd("redraw!")
  settle()
  assert(#marks(left) == total, "a full redraw adds no duplicates")

  -- Buffer B replaces A in one window before A's cleanup; B's surface survives.
  local other = attach({ "plain", "\\gamma" })
  local left_ns = render.window_namespace(left)
  api.nvim_win_set_buf(left, other)
  api.nvim_win_set_cursor(left, { 1, 0 })
  settle()
  assert(#api.nvim_buf_get_extmarks(buf, left_ns, 0, -1, {}) == 0, "replaced buffer releases the window surface")
  assert(#marks(left) == 1, "replacement buffer installs its own surface")
  assert(#marks(right) > 0, "other window keeps the first buffer's surface")
  render.detach(buf)
  assert(#marks(left) == 1, "detaching the replaced buffer preserves the replacement surface")
  assert(render.window_namespace(right) == nil, "detach releases the buffer's surfaces")
  render.detach(other)
  assert(render.window_namespace(left) == nil, "detach of the replacement releases its surface")
  vim.cmd("only")
end

persistent()
print("render-nightly-ok")
