-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-markdown-mitex-preamble.lua

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

local function assert_order(label, text, before, after)
  local before_idx = text:find(before, 1, true)
  local after_idx = text:find(after, 1, true)
  assert_true(label .. " missing before marker", before_idx ~= nil)
  assert_true(label .. " missing after marker", after_idx ~= nil)
  assert_true(label .. " order", before_idx < after_idx)
end

local function track(bufnr, source, delimiter, display_kind)
  return {
    bufnr = bufnr,
    track_id = display_kind,
    object_kind = "math",
    node_type = "math",
    row = 0,
    col = 0,
    end_row = 0,
    end_col = #source,
    source_rows = 1,
    source = source,
    source_display_kind = display_kind,
    source_facts = {
      delimiter = delimiter,
      display_kind = display_kind,
    },
  }
end

local function run()
  add_repo_to_path()

  local context = require("math-conceal.image.context")
  local wrapper = require("math-conceal.image.wrapper")
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local markdown_path = root .. "/note.md"
  local preamble_path = root .. "/mitex-preamble.tex"
  local file_definition = "\\newcommand{\\slashed}[1]{\\not{#1}}"
  local inline_definition = "\\newcommand{\\RR}{\\mathbb{R}}"
  vim.fn.writefile({ file_definition }, preamble_path)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, markdown_path)
  vim.bo[bufnr].filetype = "markdown"

  local resolver_ctx
  local binding = {
    kind = "markdown",
    source_kind = "markdown",
    scanner = "markdown",
    backend = "typst",
    wrapper = "mitex",
    filetype = "markdown",
    path = markdown_path,
    cwd = root,
    root = root,
    inputs = {},
    header = "",
    mitex_package = "@preview/mitex:0.2.7",
    mitex_preamble = inline_definition,
    mitex_preamble_file = function(ctx)
      resolver_ctx = ctx
      return preamble_path
    end,
  }
  local tracker_context = { units = {}, signature = "markdown:test" }
  local config = {
    _styling_prelude = "",
    styling_type = "none",
    math_baseline_pt = 11,
    ppi = 300,
  }

  local ctx = context.resolve(bufnr, binding, tracker_context, config)
  assert_eq("preamble resolver logical path", resolver_ctx.path, markdown_path)
  assert_eq("preamble resolver logical cwd", resolver_ctx.cwd, root)
  assert_eq("resolved preamble path", ctx.mitex_preamble_path, vim.fs.normalize(preamble_path))
  assert_eq("file then inline preamble", ctx.mitex_preamble, file_definition .. "\n" .. inline_definition)

  local inline_document =
    wrapper.build_slot_document(track(bufnr, "$\\slashed{p} \\in \\RR$", "dollar_inline", "inline"), ctx, config)
  assert_true("inline formula uses MiTeX inline call", inline_document:find("#mi(", 1, true) ~= nil)
  assert_order("inline file preamble precedes formula", inline_document, "newcommand{\\\\slashed}", "slashed{p}")
  assert_order("inline configured preamble precedes formula", inline_document, "newcommand{\\\\RR}", "slashed{p}")

  local block_document =
    wrapper.build_slot_document(track(bufnr, "$$\n\\slashed{q} \\in \\RR\n$$", "dollar_block", "block"), ctx, config)
  assert_true("block formula uses MiTeX block call", block_document:find("#mitex(", 1, true) ~= nil)
  assert_order("block preamble precedes formula", block_document, "newcommand{\\\\slashed}", "slashed{q}")

  local first_context_id = ctx.context_id
  local first_context_rev = ctx.context_rev
  local added_definition = "\\newcommand{\\ZZ}{\\mathbb{Z}}"
  vim.fn.writefile({ file_definition, added_definition }, preamble_path)
  local cached = context.resolve(bufnr, binding, tracker_context, config)
  assert_eq("preamble stays cached before explicit rerender", cached.context_id, first_context_id)
  context.invalidate_mitex_preamble(bufnr)
  local updated = context.resolve(bufnr, binding, tracker_context, config)
  assert_true("preamble content changes context id", updated.context_id ~= first_context_id)
  assert_eq("preamble content advances context revision", updated.context_rev, first_context_rev + 1)
  assert_true("updated preamble is re-read", updated.mitex_preamble:find(added_definition, 1, true) ~= nil)

  vim.api.nvim_buf_delete(bufnr, { force = true })
  vim.fn.delete(root, "rf")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("markdown-mitex-preamble-ok")
vim.cmd("qa!")
