-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-render-page-override.lua'

local function add_repo_to_path()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({
    cwd .. "/lua/?.lua",
    cwd .. "/lua/?/init.lua",
    package.path,
  }, ";")
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function assert_order(label, text, before, after)
  local before_idx = text:find(before, 1, true)
  local after_idx = text:find(after, 1, true)
  assert_true(label .. " missing before marker", before_idx ~= nil)
  assert_true(label .. " missing after marker", after_idx ~= nil)
  assert_true(label .. " order", before_idx < after_idx)
end

local function run()
  add_repo_to_path()

  local wrapper = require("math-conceal.image.wrapper")
  local bufnr = vim.api.nvim_create_buf(false, true)
  local root = vim.fn.getcwd()
  local ctx = {
    bufnr = bufnr,
    wrapper = "typst",
    buf_dir = root,
    source_root = root,
    effective_root = root,
    context_units = {
      { source = '#set page(paper: "a4")\n' },
    },
  }
  local track = {
    bufnr = bufnr,
    object_kind = "math",
    node_type = "math",
    row = 1,
    col = 0,
    end_row = 1,
    end_col = 3,
    source_rows = 1,
    prelude_count = 1,
    source = "$x$",
  }
  local config = {
    styling_type = "colorscheme",
    math_baseline_pt = 11,
  }

  local document = wrapper.build_slot_document(track, ctx, config)
  local user_page = '#set page(paper: "a4")'
  local render_page = "#set page(width: auto, height: auto, margin: (x: 0pt, y: 0pt), fill: none)"

  assert_order("render page override follows user prelude", document, user_page, render_page)
  assert_order("formula follows render page override", document, render_page, "$x$")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-render-page-override-ok")
vim.cmd("qa!")
