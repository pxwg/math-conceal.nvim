-- Run from the checkout with nvim --headless -u NONE -l scripts/bench-ascii-conceal.lua view cross
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local win = api.nvim_get_current_win()
local function report(name, samples)
  table.sort(samples)
  print(
    ("%s median=%.3f p95=%.3f ms"):format(name, samples[math.ceil(#samples / 2)], samples[math.ceil(#samples * 0.95)])
  )
end
-- Run with "native" to isolate Neovim layout and marktree work. The cursor
-- trajectory, redraw schedule and timing boundaries match the plugin run.
local native = vim.tbl_contains(arg, "native")
local view = vim.tbl_contains(arg, "view")
assert(not (native and view), "choose one display implementation")
local cross = vim.tbl_contains(arg, "cross")
local function symbol_col(j, n)
  return 1 + j * 7 + (cross and j >= n / 2 and 3 or 0)
end
local render
if not native then
  render = require("math-conceal.render")
  render.setup({ conceal = {} }, "latex")
  render.update_query("latex", [[((generic_command) @symbol (#set! @symbol conceal "X"))]])
  -- Exercise native/custom overlap resolution on edits as well as layout.
  vim.treesitter.query.set("latex", "highlights", [[((generic_command) @variable (#set! @variable conceal "N"))]])
end

local function native_surface(buf, n)
  local ns = api.nvim_create_namespace("bench-ascii-native")
  api.nvim__ns_set(ns, { wins = { win } })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "n"
  local function install(j)
    local col = symbol_col(j, n)
    api.nvim_buf_set_extmark(buf, ns, 0, col, { id = j + 1, end_col = col + 6, conceal = "X", hl_group = "Conceal" })
  end
  for j = 0, n - 1 do
    install(j)
  end
  local previous
  return ns,
    function(j)
      if previous then
        install(previous)
      end
      assert(api.nvim_buf_del_extmark(buf, ns, j + 1))
      previous = j
    end
end

for _, n in ipairs({ 32, 512, 2048 }) do
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, buf)
  local half = string.rep("\\alpha ", n / 2)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "$" .. half .. (cross and "$ $" or "") .. half .. "$" })
  vim.bo[buf].filetype = "tex"
  local ns, flip
  if native then
    ns, flip = native_surface(buf, n)
  else
    assert(render.attach(buf, "latex"))
    vim.treesitter.get_parser(buf, "latex"):parse()
  end
  if view then
    require("math-conceal.ascii-view").open()
  end
  vim.cmd("redraw!")
  local previous
  local move, frame, full = {}, {}, {}
  for i = 1, 120 do
    local start = vim.uv.hrtime()
    local j = (i * 37) % n
    if cross then
      j = (math.floor(i / 2) * 37) % (n / 2) + (i % 2) * (n / 2)
    end
    local col = symbol_col(j, n)
    if view then
      col = col - j * 5 + (previous and previous < j and 5 or 0)
    end
    api.nvim_win_set_cursor(win, { 1, col })
    if native then
      flip(j)
    else
      api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_win_get_buf(win) })
    end
    previous = j
    local moved = vim.uv.hrtime()
    vim.cmd("redraw")
    local drawn = vim.uv.hrtime()
    vim.cmd("redraw!")
    local forced = vim.uv.hrtime()
    if i > 20 then
      move[#move + 1] = (moved - start) / 1e6
      full[#full + 1] = (forced - drawn) / 1e6
      frame[#frame + 1] = (drawn - start) / 1e6
    end
  end
  report(n .. " symbols, cursor", move)
  report(n .. " symbols, cursor + redraw", frame)
  report(n .. " symbols, redraw!", full)
  if view then
    local text = api.nvim_get_current_line()
    assert(select(2, text:gsub("X", "")) == n - 1 and text:find("\\alpha", 1, true))
    require("math-conceal.ascii-view").leave()
    assert(api.nvim_win_get_buf(win) == buf and api.nvim_win_get_cursor(win)[2] == symbol_col(previous, n))
  end
  if not native then
    local edits = {}
    for i = 1, 100 do
      local start = vim.uv.hrtime()
      api.nvim_buf_set_text(buf, 0, 1, 0, 7, { i % 2 == 1 and "\\gamma" or "\\alpha" })
      vim.treesitter.get_parser(buf, "latex"):parse()
      if view then
        require("math-conceal.ascii-view").open()
      end
      vim.cmd("redraw!")
      edits[i] = (vim.uv.hrtime() - start) / 1e6
      if view then
        require("math-conceal.ascii-view").leave()
      end
    end
    report(n .. (view and " symbols, edit + parse + project + redraw!" or " symbols, edit + parse + redraw!"), edits)
  end
  -- Outside the timed section, verify that the measured surface did the work.
  ns = ns or (render and render.window_namespace and render.window_namespace(win))
  if ns and not view then
    local marks = api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    assert(#marks == n - 1, "exactly the symbol under the cursor should be revealed")
    for _, mark in ipairs(marks) do
      assert(mark[4].conceal == "X", "custom conceal takes precedence over native conceal")
    end
  end
  if render then
    render.detach(buf)
  end
  api.nvim_buf_delete(buf, { force = true })
end
