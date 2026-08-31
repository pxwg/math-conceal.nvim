-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-image-unload-resume.lua'

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

  local attach_count = 0
  local detach_count = 0
  local projection_detach_count = 0

  package.loaded["math-conceal.image.tracker"] = {
    attach = function()
      attach_count = attach_count + 1
      return true
    end,
    detach = function()
      detach_count = detach_count + 1
    end,
    sync_cursor_nested = function()
      return true
    end,
  }
  package.loaded["math-conceal.image.projection"] = {
    detach = function()
      projection_detach_count = projection_detach_count + 1
    end,
    on_tracker_repair = function() end,
    on_layout_change = function() end,
    force_render = function() end,
    sync_cursor = function() end,
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

  assert_true("manual attach succeeds", image.attach_buf(bufnr))
  assert_eq("initial attach count", attach_count, 1)

  vim.api.nvim_exec_autocmds("BufUnload", { buffer = bufnr, modeline = false })
  assert_eq("projection detached on unload", projection_detach_count, 1)
  assert_eq("tracker detached on unload", detach_count, 1)
  assert_eq("binding cleared on unload", image.get_binding(bufnr), nil)

  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
  assert_eq("manual attach resumes on read", attach_count, 2)
  assert_true("binding restored after read", image.get_binding(bufnr) ~= nil)

  image.disable_buf(bufnr)
  assert_eq("manual disable clears binding", image.get_binding(bufnr), nil)
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
  assert_eq("manual disable does not resume on read", attach_count, 2)

  assert_true("manual attach succeeds again", image.attach_buf(bufnr))
  vim.api.nvim_exec_autocmds("BufUnload", { buffer = bufnr, modeline = false })
  vim.api.nvim_exec_autocmds("BufDelete", { buffer = bufnr, modeline = false })
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
  assert_eq("delete clears resume intent", attach_count, 3)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("image-unload-resume-ok")
vim.cmd("qa!")
