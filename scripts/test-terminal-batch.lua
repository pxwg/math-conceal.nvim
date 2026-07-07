-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-terminal-batch.lua'

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

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function run()
  add_repo_to_path()

  package.loaded["math-conceal.image.terminal"] = nil
  package.loaded["math-conceal.image.state"] = package.loaded["math-conceal.image.state"]
    or {
      release_placement_id = function() end,
      release_image_id = function() end,
    }

  local writes = {}
  local original_ui_send = vim.api.nvim_ui_send
  vim.api.nvim_ui_send = function(data)
    writes[#writes + 1] = data
    return true
  end

  local terminal = require("math-conceal.image.terminal")
  terminal.place_image(1, 10, 2, 3)
  assert_eq("unbatched place flushes immediately", #writes, 1)

  terminal.batch(function()
    terminal.place_image(1, 11, 2, 3)
    terminal.place_image(1, 12, 2, 3)
  end)
  assert_eq("batched places flush once", #writes, 2)
  assert_true("batched write includes first placement", writes[2]:find("p=11", 1, true) ~= nil)
  assert_true("batched write includes second placement", writes[2]:find("p=12", 1, true) ~= nil)

  terminal.batch(function()
    terminal.batch(function()
      terminal.place_image(1, 13, 2, 3)
    end)
    assert_eq("nested batch does not flush early", #writes, 2)
    terminal.place_image(1, 14, 2, 3)
  end)
  assert_eq("nested batch flushes at outer boundary", #writes, 3)
  assert_true("nested batch includes inner placement", writes[3]:find("p=13", 1, true) ~= nil)
  assert_true("nested batch includes outer placement", writes[3]:find("p=14", 1, true) ~= nil)

  vim.api.nvim_ui_send = original_ui_send
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("terminal-batch-ok")
vim.cmd("qa!")
