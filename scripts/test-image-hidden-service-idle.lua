-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-image-hidden-service-idle.lua'

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

  local tracker_attach_count = 0
  local preview_clear_count = 0
  local preview_stop_count = 0
  local full_idle_stop_count = 0

  package.loaded["math-conceal.image.tracker"] = {
    attach = function()
      tracker_attach_count = tracker_attach_count + 1
      return true
    end,
    detach = function() end,
    sync_cursor_nested = function()
      return true
    end,
  }
  package.loaded["math-conceal.image.projection"] = {
    detach = function() end,
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
  package.loaded["math-conceal.image.preview"] = {
    clear = function(_, opts)
      if opts and opts.skip_idle_stop == true then
        preview_clear_count = preview_clear_count + 1
      end
    end,
  }
  package.loaded["math-conceal.image.session"] = {
    stop = function(_, kind)
      if kind == "preview" then
        preview_stop_count = preview_stop_count + 1
      end
    end,
    stop_if_idle = function(_, kind)
      if kind == "full" then
        full_idle_stop_count = full_idle_stop_count + 1
      end
      return true
    end,
  }

  local image = require("math-conceal.image")
  image.setup({
    enabled_by_default = false,
    styling_type = "none",
    hidden_service_idle_ms = 20,
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

  local image_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(image_buf)
  vim.bo[image_buf].filetype = "typst"
  assert_true("manual attach succeeds", image.attach_buf(image_buf))
  assert_eq("tracker attached once", tracker_attach_count, 1)

  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(other_buf)
  vim.api.nvim_exec_autocmds("BufHidden", { buffer = image_buf, modeline = false })

  assert_true(
    "hidden idle timer stops services",
    vim.wait(200, function()
      return preview_clear_count == 1 and preview_stop_count == 1 and full_idle_stop_count == 1
    end, 5)
  )

  local retry_attempts = 0
  package.loaded["math-conceal.image.session"].stop_if_idle = function(_, kind)
    if kind == "full" then
      full_idle_stop_count = full_idle_stop_count + 1
      retry_attempts = retry_attempts + 1
    end
    return retry_attempts >= 2
  end
  image.config.hidden_service_idle_ms = 10
  image._schedule_hidden_service_stop(image_buf)
  assert_true(
    "active full render is retried instead of canceled",
    vim.wait(200, function()
      return retry_attempts == 2 and full_idle_stop_count == 3
    end, 5)
  )

  package.loaded["math-conceal.image.session"].stop_if_idle = function(_, kind)
    if kind == "full" then
      full_idle_stop_count = full_idle_stop_count + 1
    end
    return true
  end
  image.config.hidden_service_idle_ms = -1
  image._schedule_hidden_service_stop(image_buf)
  vim.wait(50, function()
    return false
  end, 5)
  assert_eq("negative timeout keeps hidden services alive", full_idle_stop_count, 3)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("image-hidden-service-idle-ok")
vim.cmd("qa!")
