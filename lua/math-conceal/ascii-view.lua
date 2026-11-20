-- A display buffer for navigation. All user edits take place in the source buffer.
local api = vim.api
local render = require("math-conceal.render")
local M = {}
local ns = api.nvim_create_namespace("math-conceal.ascii-view")
local views, watching = {}, {}

local function last_start(items, key, col)
  local lo, hi = 0, #items
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if items[mid][key] <= col then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return items[lo]
end

-- All coordinates are byte boundaries. Equal reveal ranges (e.g. Markdown
-- links) form one group even when only parts of their source are concealed.
local function project_row(line, marks, row)
  -- Captures from a single query usually arrive in source order. Merged
  -- query streams can restart at an earlier column.
  for i = 2, #marks do
    if marks[i].col < marks[i - 1].col then
      table.sort(marks, function(a, b)
        return a.col < b.col
      end)
      break
    end
  end
  local pieces, tokens, groups = {}, {}, {}
  local pos, delta, group = 0, 0, nil
  for _, m in ipairs(marks) do
    local r = m.expand_range
    if
      m.row ~= row
      or m.end_row ~= row
      or m.kind ~= "conceal"
      or r[1] ~= row
      or r[3] ~= row
      or m.col < pos
      or m.end_col <= m.col
      or r[2] > m.col
      or r[4] < m.end_col
    then
      return line
    end
    local start = m.col + delta
    local token = {
      first = m.col,
      last = m.end_col,
      display = start,
      finish = start + #m.conceal,
      hl = m.hl_group,
      priority = m.priority,
    }
    tokens[#tokens + 1] = token
    if not group or group.first ~= r[2] or group.last ~= r[4] then
      if group and r[2] < group.last then
        return line
      end
      -- Most symbols are their own reveal group. Allocate a separate span
      -- only for captures that expand surrounding syntax (e.g. a whole link).
      group = r[2] == m.col and r[4] == m.end_col and token or { first = r[2], last = r[4], display = r[2] + delta }
      group.row, group.token_start = row, #tokens
      groups[#groups + 1] = group
    end
    pieces[#pieces + 1] = line:sub(pos + 1, m.col)
    pieces[#pieces + 1] = m.conceal
    delta = token.finish - m.end_col
    group.token_end = #tokens
    group.finish = group.last + delta
    pos = m.end_col
  end
  pieces[#pieces + 1] = line:sub(pos + 1)
  local compact = table.concat(pieces)
  return compact, { source = line, compact = compact, tokens = tokens, groups = groups }
end

local function source_col(s, row, col)
  local line = s.rows[row]
  if not line then
    return col
  end
  local g = s.active
  if g and g.row == row and col >= g.display then
    if col < g.display + g.last - g.first then
      return g.first + col - g.display
    end
    col = col - (g.last - g.first) + (g.finish - g.display)
  end
  local t = last_start(line.tokens, "display", col)
  if not t then
    return col
  end
  return col < t.finish and t.first or t.last + col - t.finish
end

local function highlight(view, row, t)
  if t.hl and t.display < t.finish then
    t.id = api.nvim_buf_set_extmark(view, ns, row, t.display, {
      end_col = t.finish,
      hl_group = t.hl,
      priority = t.priority,
      right_gravity = true,
      end_right_gravity = false,
    })
  end
end

local function set_group(s, g, reveal)
  local line = s.rows[g.row]
  local text = reveal and line.source:sub(g.first + 1, g.last) or line.compact:sub(g.display + 1, g.finish)
  local finish = reveal and g.finish or g.display + g.last - g.first
  if reveal then
    for i = g.token_start, g.token_end do
      local t = line.tokens[i]
      if t.id then
        api.nvim_buf_del_extmark(s.view, ns, t.id)
        t.id = nil
      end
    end
  end
  api.nvim_buf_set_text(s.view, g.row, g.display, g.row, finish, { text })
  if not reveal then
    for i = g.token_start, g.token_end do
      highlight(s.view, g.row, line.tokens[i])
    end
  end
end

-- Rows with overlapping captures or multiline marks retain their original byte
-- geometry. Let Neovim arbitrate priorities and measure those rows natively.
local function set_native(s, entry, show)
  if show and not entry.id then
    local m = entry.mark
    entry.id = api.nvim_buf_set_extmark(s.view, ns, m.row, m.col, {
      end_row = m.end_row,
      end_col = m.end_col,
      priority = m.priority,
      conceal = m.conceal,
      conceal_lines = m.conceal_lines,
      hl_group = m.hl_group,
      strict = false,
    })
  elseif not show and entry.id then
    api.nvim_buf_del_extmark(s.view, ns, entry.id)
    entry.id = nil
  end
end

local function native_cursor(s, row, col)
  local function update(entries)
    for _, entry in ipairs(entries or {}) do
      local r = entry.mark.expand_range
      local inside = (row > r[1] or row == r[1] and col >= r[2]) and (row < r[3] or row == r[3] and col < r[4])
      set_native(s, entry, not inside)
    end
  end
  if s.cursor_row and s.cursor_row ~= row then
    update(s.native[s.cursor_row])
  end
  update(s.native[row])
  s.cursor_row = row
end

local function position(s, win, row, col)
  if next(s.native) then
    native_cursor(s, row, col)
  end
  local line = s.rows[row]
  local g = line and last_start(line.groups, "first", col)
  if g and col >= g.last then
    g = nil
  end
  if g ~= s.active then
    vim.bo[s.view].modifiable = true
    if s.active then
      set_group(s, s.active, false)
    end
    if g then
      set_group(s, g, true)
    end
    s.active = g
    vim.bo[s.view].modified = vim.bo[s.source].modified
    vim.bo[s.view].modifiable = false
  end
  local display = col
  if g then
    display = g.display + col - g.first
  elseif line then
    local t = last_start(line.tokens, "first", col)
    if t then
      display = t.finish + col - t.last
    end
  end
  local p = api.nvim_win_get_cursor(win)
  if p[1] ~= row + 1 or p[2] ~= display then
    api.nvim_win_set_cursor(win, { row + 1, display })
  end
end

local function source_marks(source)
  local hl = vim.treesitter.highlighter.active[source]
  if hl then
    hl.tree:parse(true)
  end
  return render.collect_display_marks(source, { toprow = 0, botrow = api.nvim_buf_line_count(source) - 1 })
end

local function rebuild(s, marks)
  local source = s.source
  marks = marks or source_marks(source)
  local lines = api.nvim_buf_get_lines(source, 0, -1, false)
  local by_row, raw = {}, {}
  for _, m in ipairs(marks) do
    if m.row ~= m.end_row or m.kind == "line" then
      for row = m.row, m.end_row do
        raw[row] = true
      end
    end
    by_row[m.row] = by_row[m.row] or {}
    table.insert(by_row[m.row], m)
  end
  s.rows, s.active = {}, nil
  for row, entries in pairs(by_row) do
    if not raw[row] then
      lines[row + 1], s.rows[row] = project_row(lines[row + 1], entries, row)
      raw[row] = not s.rows[row]
    end
  end
  vim.bo[s.view].modifiable = true
  api.nvim_buf_clear_namespace(s.view, ns, 0, -1)
  api.nvim_buf_set_lines(s.view, 0, -1, false, lines)
  for row, line in pairs(s.rows) do
    for _, t in ipairs(line.tokens) do
      highlight(s.view, row, t)
    end
  end
  s.native, s.cursor_row = {}, nil
  for _, m in ipairs(marks) do
    if raw[m.row] then
      local entry = { mark = m }
      set_native(s, entry, true)
      for row = m.expand_range[1], m.expand_range[3] do
        s.native[row] = s.native[row] or {}
        table.insert(s.native[row], entry)
      end
    end
  end
  vim.bo[s.view].modified = vim.bo[s.source].modified
  vim.bo[s.view].modifiable = false
  s.tick = api.nvim_buf_get_changedtick(source)
end

local function cursor(s, win)
  local p = api.nvim_win_get_cursor(win)
  return p[1] - 1, source_col(s, p[1] - 1, p[2])
end

local function sync(s, win)
  local row, col = cursor(s, win)
  if s.tick ~= api.nvim_buf_get_changedtick(s.source) then
    rebuild(s)
    row = math.min(row, api.nvim_buf_line_count(s.source) - 1)
    col = math.min(col, #api.nvim_buf_get_lines(s.source, row, row + 1, false)[1])
  end
  position(s, win, row, col)
end

local function watch(source)
  if watching[source] then
    return
  end
  watching[source] = true
  local queued = false
  api.nvim_buf_attach(source, false, {
    on_lines = function()
      if queued then
        return
      end
      queued = true
      vim.schedule(function()
        queued = false
        if not api.nvim_buf_is_loaded(source) then
          return
        end
        for _, s in pairs(views) do
          if
            s.source == source
            and api.nvim_win_is_valid(s.win)
            and api.nvim_win_get_buf(s.win) == s.view
            and s.tick ~= api.nvim_buf_get_changedtick(source)
          then
            sync(s, s.win)
          end
        end
      end)
    end,
    on_detach = function()
      watching[source] = nil
      vim.schedule(function()
        for view, s in pairs(views) do
          if s.source == source and api.nvim_buf_is_valid(view) then
            api.nvim_buf_delete(view, { force = true })
          end
        end
      end)
    end,
  })
end

function M.leave()
  local s = assert(views[api.nvim_get_current_buf()])
  local win = api.nvim_get_current_win()
  sync(s, win)
  local row, col = cursor(s, win)
  vim.w[win].math_conceal_source = s.source
  -- All edits already belong to the source. The disposable view mirrors
  -- its modified flag so :update and :x write through.
  vim.cmd(("keepalt hide buffer! %d"):format(s.source))
  api.nvim_win_set_cursor(win, { row + 1, col })
end

local function source_command(s, key)
  local win = api.nvim_get_current_win()
  local register, count = vim.v.register, vim.v.count
  M.leave()
  -- Let Neovim finish the command (including operator motions, Insert or
  -- Visual mode, and user mappings) before projecting the source again.
  api.nvim_create_autocmd("SafeState", {
    callback = function()
      if api.nvim_get_current_win() ~= win or api.nvim_get_current_buf() ~= s.source then
        return true
      end
      if vim.fn.mode(1) == "n" then
        if render.is_attached(s.source) then
          M.open()
        end
        return true
      end
    end,
  })
  local prefix = (register ~= '"' and '"' .. register or "") .. (count > 0 and tostring(count) or "")
  api.nvim_feedkeys(prefix .. api.nvim_replace_termcodes(key, true, false, true), "mi", false)
end

function M.open(marks)
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local p = api.nvim_win_get_cursor(win)
  local level, modes = vim.wo[win].conceallevel, vim.wo[win].concealcursor
  local view = api.nvim_create_buf(false, true)
  local s = { source = buf, view = view, win = win }
  views[view] = s
  vim.bo[view].buftype = "acwrite"
  vim.bo[view].bufhidden = "wipe"
  vim.bo[view].undolevels = -1
  vim.bo[view].tabstop = vim.bo[buf].tabstop
  vim.bo[view].vartabstop = vim.bo[buf].vartabstop
  api.nvim_buf_set_name(
    view,
    ("math-conceal://%d/%s"):format(view, vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t"))
  )
  api.nvim_create_autocmd("BufWipeout", {
    buffer = view,
    once = true,
    callback = function()
      views[view] = nil
    end,
  })
  local ok, err = pcall(rebuild, s, marks)
  if not ok then
    api.nvim_buf_delete(view, { force = true })
    error(err)
  end
  vim.w[win].math_conceal_source = nil
  vim.cmd(("keepalt hide buffer %d"):format(view))
  vim.wo[win].conceallevel, vim.wo[win].concealcursor = level, modes
  position(s, win, p[1] - 1, p[2])
  watch(buf)
  api.nvim_create_autocmd("CursorMoved", {
    buffer = view,
    callback = function()
      sync(s, api.nvim_get_current_win())
    end,
  })
  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = view,
    callback = function()
      api.nvim_buf_call(buf, function()
        vim.cmd.write({ bang = vim.v.cmdbang == 1 })
      end)
      vim.bo[view].modified = vim.bo[buf].modified
    end,
  })
  -- A split needs its own expanded range, independent of its sibling.
  api.nvim_create_autocmd("WinEnter", {
    buffer = view,
    callback = function()
      local other = api.nvim_get_current_win()
      if other ~= win then
        vim.schedule(function()
          if api.nvim_get_current_win() == other and api.nvim_get_current_buf() == view then
            M.leave()
            M.open()
          end
        end)
      end
    end,
  })
  for _, key in ipairs({
    "i",
    "a",
    "I",
    "A",
    "o",
    "O",
    "R",
    "c",
    "C",
    "d",
    "D",
    "s",
    "S",
    "x",
    "X",
    "p",
    "P",
    "r",
    "y",
    "Y",
    "v",
    "V",
    "<C-v>",
    "u",
    "<C-r>",
  }) do
    vim.keymap.set("n", key, function()
      source_command(s, key)
    end, { buffer = view })
  end
end

-- FileType attachment also runs for previews, unnamed host buffers and image
-- surfaces. Only normal file windows should enter the interactive view.
function M.open_file(buf)
  local win = api.nvim_get_current_win()
  local hidden = vim.bo[buf].bufhidden
  if
    vim.w[win].math_conceal_source == buf
    or vim.bo[buf].buftype ~= ""
    or not vim.bo[buf].buflisted
    or api.nvim_buf_get_name(buf) == ""
    or (hidden ~= "" and hidden ~= "hide")
    or vim.api.nvim_win_get_config(win).relative ~= ""
    or vim.wo[win].diff
    or vim.wo[win].conceallevel ~= 2
    or vim.api.nvim_get_mode().mode ~= "n"
  then
    return
  end
  local attachment = require("math-conceal.nvim").get_attachment(buf)
  if not attachment or not attachment.unicode or attachment.image or attachment.mode ~= "edit" then
    return
  end
  local marks = source_marks(buf)
  if #marks > 0 then
    M.open(marks)
  end
end

return M
