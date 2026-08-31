-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-window-options.lua'

local function add_repo_to_path()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({
    cwd .. "/lua/?.lua",
    cwd .. "/lua/?/init.lua",
    package.path,
  }, ";")
end

local function assert_eq(label, actual, expected)
  if actual ~= expected then
    error(string.format("%s mismatch\nexpected: %q\nactual:   %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_win(label, winid, conceallevel, concealcursor)
  assert_eq(label .. " conceallevel", vim.wo[winid].conceallevel, conceallevel)
  assert_eq(label .. " concealcursor", vim.wo[winid].concealcursor, concealcursor)
end

local function run()
  add_repo_to_path()

  local winopts = require("math-conceal.window-options")
  winopts.setup({ conceallevel = 2, concealcursor = "n" })

  local managed = vim.api.nvim_create_buf(false, true)
  local plain = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(managed, 0, -1, false, { "$x$" })
  vim.api.nvim_buf_set_lines(plain, 0, -1, false, { "plain" })

  local win1 = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win1, managed)
  vim.wo[win1].conceallevel = 1
  vim.wo[win1].concealcursor = ""

  winopts.attach(managed, "render")
  assert_win("managed window receives plugin options", win1, 2, "n")

  vim.cmd("vsplit")
  local win2 = vim.api.nvim_get_current_win()
  winopts.sync(managed)
  assert_win("split showing managed buffer receives plugin options", win2, 2, "n")

  vim.api.nvim_win_set_buf(win2, plain)
  winopts.sync()
  assert_win("unmanaged split restores inherited options", win2, 1, "")
  assert_win("original managed window remains configured", win1, 2, "n")

  winopts.detach(managed, "render")
  assert_win("last owner detach restores original window options", win1, 1, "")

  vim.api.nvim_set_current_win(win1)
  vim.api.nvim_win_set_buf(win1, managed)
  vim.wo[win1].conceallevel = 0
  vim.wo[win1].concealcursor = ""
  winopts.attach(managed, "render")
  winopts.attach(managed, "image")
  assert_win("multi-owner attach applies once", win1, 2, "n")
  winopts.detach(managed, "render")
  assert_win("first owner detach keeps options", win1, 2, "n")
  winopts.detach(managed, "image")
  assert_win("final owner detach restores options", win1, 0, "")

  winopts.setup({ concealcursor = "nci" })
  winopts.attach(managed, "render")
  assert_win("setup opt controls attached windows", win1, 2, "nci")
  winopts.detach(managed, "render")
  assert_win("configured opt detach restores options", win1, 0, "")
  winopts.setup({ concealcursor = "n" })

  vim.wo[win1].conceallevel = 1
  vim.wo[win1].concealcursor = ""
  winopts.attach(managed, "render")
  vim.wo[win1].concealcursor = "i"
  winopts.detach(managed, "render")
  assert_win("manual window option changes are not overwritten", win1, 2, "i")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("window-options-ok")
vim.cmd("qa!")
