-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-image-capability-health.lua

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local capability = require("math-conceal.image.capability").inspect()
  assert(capability.nvim_011 == true, "test Neovim must support the image path")
  assert(capability.apis.nvim__ns_set == true, "nvim__ns_set must be available")
  assert(capability.apis.nvim_win_text_height == true, "nvim_win_text_height must be available")
  assert(require("math-conceal.image.placement").available(), "window-scoped placement must be available")

  local reports = {}
  local old_health = vim.health
  vim.health = {
    start = function(message)
      reports[#reports + 1] = { "start", message }
    end,
    ok = function(message)
      reports[#reports + 1] = { "ok", message }
    end,
    warn = function(message)
      reports[#reports + 1] = { "warn", message }
    end,
    error = function(message)
      reports[#reports + 1] = { "error", message }
    end,
  }
  require("math-conceal.health").check()
  vim.health = old_health
  assert(#reports >= 7, "health check should report all image capabilities")
  assert(reports[1][1] == "start" and reports[1][2] == "math-conceal", "health section must be named")
  print("image-capability-health-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
