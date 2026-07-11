-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-realization-boundary.lua'

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local function assert_eq(label, actual, expected)
    if actual ~= expected then
      error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "  $x$  ",
    "$x$ after",
    "before $x$",
    "before $x$ after",
    "before $",
    "x",
    "$ after",
  })
  local boundary = require("math-conceal.image.realization.boundary")

  assert_eq("inline has no boundary role", boundary.role({ bufnr = bufnr }, "inline"), nil)
  assert_eq(
    "isolated block",
    boundary.role({ bufnr = bufnr, row = 0, col = 2, end_row = 0, end_col = 5 }, "block"),
    "isolated"
  )
  assert_eq(
    "suffix block",
    boundary.role({ bufnr = bufnr, row = 1, col = 0, end_row = 1, end_col = 3 }, "block"),
    "suffix"
  )
  assert_eq(
    "prefix block",
    boundary.role({ bufnr = bufnr, row = 2, col = 7, end_row = 2, end_col = 10 }, "block"),
    "prefix"
  )
  assert_eq(
    "same-row double boundary is sandwich",
    boundary.role({ bufnr = bufnr, row = 3, col = 7, end_row = 3, end_col = 10 }, "block"),
    "sandwich"
  )
  assert_eq(
    "multi-row double boundary remains prefix",
    boundary.role({ bufnr = bufnr, row = 4, col = 7, end_row = 6, end_col = 1 }, "block"),
    "prefix"
  )

  local registry = require("math-conceal.image.realization")
  local ok = pcall(registry.register, "invalid", {})
  assert_eq("registry rejects incomplete adapters", ok, false)

  print("realization-boundary-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
