-- Run with:
--   MATH_CONCEAL_SERVICE=service/target/release/typst-concealer-service \
--     nvim --headless -u NONE '+luafile scripts/test-image-shared-service.lua'

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
  local binary = vim.env.MATH_CONCEAL_SERVICE or "service/target/release/typst-concealer-service"
  assert_eq("service executable", vim.fn.executable(binary), 1)

  local session = require("math-conceal.image.session")
  local bufnr = vim.api.nvim_create_buf(false, true)
  local binding = { service_binary = binary }
  local full = session.ensure(bufnr, binding, "full")
  local preview = session.ensure(bufnr, binding, "preview")

  assert_true("full service starts", full ~= nil and full.job_id ~= nil)
  assert_true("preview reuses full service", preview == full)
  assert_eq("shared service pid", vim.fn.jobpid(preview.job_id), vim.fn.jobpid(full.job_id))

  session.stop(bufnr, "preview")
  assert_eq("preview lane reset keeps process alive", vim.fn.jobwait({ full.job_id }, 0)[1], -1)

  session.stop(bufnr)
  assert_true(
    "shared service stops",
    vim.wait(1000, function()
      return vim.fn.jobwait({ full.job_id }, 0)[1] ~= -1
    end, 10)
  )
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("image-shared-service-ok")
vim.cmd("qa!")
