-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-image-preview-idle-service.lua'

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

  local stopped = {}
  local canceled = 0
  package.loaded["math-conceal.image"] = {
    config = {
      preview_idle_timeout_ms = 20,
    },
  }
  package.loaded["math-conceal.image.session"] = {
    cancel_live_preview = function()
      canceled = canceled + 1
    end,
    stop = function(bufnr, kind)
      stopped[#stopped + 1] = { bufnr = bufnr, kind = kind }
    end,
  }

  local preview = require("math-conceal.image.preview")
  local bufnr = vim.api.nvim_create_buf(false, true)

  preview.clear(bufnr)
  assert_eq("clear cancels pending preview", canceled, 1)
  assert_true(
    "idle timer stops preview service",
    vim.wait(200, function()
      return #stopped == 1
    end, 5)
  )
  assert_eq("stopped buffer", stopped[1].bufnr, bufnr)
  assert_eq("stopped service kind", stopped[1].kind, "preview")

  package.loaded["math-conceal.image"].config.preview_idle_timeout_ms = -1
  preview.clear(bufnr)
  vim.wait(50, function()
    return false
  end, 5)
  assert_eq("negative timeout keeps preview service alive", #stopped, 1)

  preview.detach(bufnr)
  vim.wait(50, function()
    return false
  end, 5)
  assert_eq("detach does not schedule idle stop", #stopped, 1)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("image-preview-idle-service-ok")
vim.cmd("qa!")
