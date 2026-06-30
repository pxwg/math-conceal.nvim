-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-image-cursor-sync-debounce.lua'

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

  local tracker_cursor_calls = 0
  local projection_cursor_calls = 0
  local attached_bufnr = nil

  package.loaded["math-conceal.image.tracker"] = {
    attach = function(bufnr)
      attached_bufnr = bufnr
      return true
    end,
    detach = function() end,
    sync_cursor_nested = function()
      tracker_cursor_calls = tracker_cursor_calls + 1
      return true
    end,
  }
  package.loaded["math-conceal.image.projection"] = {
    detach = function() end,
    on_tracker_repair = function() end,
    sync_cursor = function()
      projection_cursor_calls = projection_cursor_calls + 1
    end,
  }
  package.loaded["math-conceal.image.state"] = {
    refresh_cell_px_size = function()
      return false
    end,
  }

  local image = require("math-conceal.image")
  image.setup({
    enabled_by_default = false,
    styling_type = "none",
    renderers = {
      typst = {
        filetypes = { "typst" },
        service_binary = "typst-concealer-service",
        live_debounce = 0,
        source_kind = "typst",
        scanner = "typst",
        backend = "typst",
        wrapper = "typst",
        inputs = {},
        render_paths = { exclude = {} },
      },
    },
  })

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "typst"
  assert_true("attach succeeds", image.attach_buf(bufnr))
  assert_eq("tracker attach bufnr", attached_bufnr, bufnr)

  for _ = 1, 5 do
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr, modeline = false })
  end
  assert_eq("cursor moved sync is deferred", tracker_cursor_calls, 0)
  assert_true(
    "cursor moved sync eventually runs once",
    vim.wait(200, function()
      return tracker_cursor_calls == 1 and projection_cursor_calls == 1
    end, 5)
  )

  vim.api.nvim_exec_autocmds("ModeChanged", { buffer = bufnr, modeline = false })
  assert_eq("mode changed tracker sync is immediate", tracker_cursor_calls, 2)
  assert_eq("mode changed projection sync is immediate", projection_cursor_calls, 2)

  tracker_cursor_calls = 0
  projection_cursor_calls = 0
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr, modeline = false })
  assert_eq("preempted cursor moved sync is deferred", tracker_cursor_calls, 0)
  vim.api.nvim_exec_autocmds("ModeChanged", { buffer = bufnr, modeline = false })
  assert_eq("preempting mode changed tracker sync is immediate", tracker_cursor_calls, 1)
  assert_eq("preempting mode changed projection sync is immediate", projection_cursor_calls, 1)
  vim.wait(50, function()
    return false
  end, 5)
  assert_eq("preempted cursor timer does not run tracker sync", tracker_cursor_calls, 1)
  assert_eq("preempted cursor timer does not run projection sync", projection_cursor_calls, 1)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("image-cursor-sync-debounce-ok")
vim.cmd("qa!")
