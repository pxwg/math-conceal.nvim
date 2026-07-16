-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-attach-api.lua

local function add_runtime_paths()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local treesitter = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
  if vim.fn.isdirectory(treesitter) == 1 then
    vim.opt.runtimepath:append(treesitter)
  end
end

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(
      string.format("%s mismatch\nexpected: %s\nactual:   %s", label, vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function set_source(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function display_marks(bufnr)
  return require("math-conceal.render").collect_display_marks(bufnr, {
    toprow = 0,
    botrow = vim.api.nvim_buf_line_count(bufnr),
  })
end

local function run()
  add_runtime_paths()

  for _, lang in ipairs({ "latex", "markdown", "markdown_inline", "typst" }) do
    assert_true("Tree-sitter parser is installed for " .. lang, pcall(vim.treesitter.language.add, lang))
  end

  local conceal = require("math-conceal")
  conceal.setup({ image = { enabled = false } })

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "snacks_picker_preview"
  vim.wo.conceallevel = 0
  vim.wo.concealcursor = ""
  set_source(bufnr, { "$ alpha + beta $" })

  local detected = conceal.resolve_source(bufnr, { path = "/tmp/math-conceal-detected.md" })
  assert_eq("virtual source resolves from real path", detected.kind, "markdown")
  assert_eq("virtual source keeps detected filetype", detected.filetype, "markdown")

  local typst = conceal.attach(bufnr, {
    source = {
      kind = "typst",
      filetype = "typst",
      path = "/tmp/math-conceal-attach.typ",
    },
    mode = "presentation",
    surfaces = { unicode = true, image = false },
    owner = "preview",
  })
  assert_true("Typst attachment is current", typst:is_current())
  assert_true("Typst Unicode surface attached", typst.unicode)
  assert_eq("Typst logical source", conceal.get_attachment(bufnr).source.kind, "typst")
  assert_eq("presentation mode applied", conceal.get_buffer_config(bufnr).mode, "presentation")
  assert_eq("attachment applies conceallevel", vim.wo.conceallevel, 2)
  assert_true("Typst conceal marks collected", #display_marks(bufnr) > 0)
  assert_eq("Typst root parser", vim.treesitter.get_parser(bufnr, "typst"):lang(), "typst")

  local renewed = conceal.attach(bufnr, {
    source = typst.source,
    mode = "presentation",
    surfaces = { unicode = true, image = false },
    owner = "preview",
  })
  assert_true("renewed attachment is current", renewed:is_current())
  assert_true("replaced handle becomes stale", not typst:is_current())
  assert_true("stale handle cannot detach renewed owner", not typst:detach())

  set_source(bufnr, { "Inline $\\alpha + \\beta$." })
  local markdown_source = {
    kind = "markdown",
    filetype = "markdown",
    path = "/tmp/math-conceal-attach.md",
  }
  local rebound = conceal.attach(bufnr, {
    source = markdown_source,
    mode = "presentation",
    surfaces = { unicode = true, image = false },
    owner = "preview",
  })
  assert_true("source replacement invalidates old owner handle", not renewed:is_current())
  assert_eq("source replacement changes root parser", vim.treesitter.get_parser(bufnr, "markdown"):lang(), "markdown")
  assert_true("source replacement produces Markdown marks", #display_marks(bufnr) > 0)

  rebound:detach()
  assert_eq("presentation mode restored", conceal.get_buffer_config(bufnr).mode, "edit")
  assert_eq("attachment restores conceallevel", vim.wo.conceallevel, 0)
  assert_eq("last owner removes attachment", conceal.get_attachment(bufnr), nil)
  assert_true("last owner detaches Unicode renderer", not require("math-conceal.render").is_attached(bufnr))

  local markdown = conceal.attach(bufnr, {
    source = markdown_source,
    surfaces = { unicode = true, image = false },
    owner = "preview",
  })
  assert_eq("Markdown logical source", conceal.get_attachment(bufnr).source.kind, "markdown")
  assert_eq("Markdown root parser", vim.treesitter.get_parser(bufnr, "markdown"):lang(), "markdown")
  assert_true("Markdown conceal marks collected", #display_marks(bufnr) > 0)

  local shared = conceal.attach(bufnr, {
    source = markdown.source,
    surfaces = { unicode = true, image = false },
    owner = "second-owner",
  })
  assert_eq("same source supports multiple owners", conceal.get_attachment(bufnr).owner_count, 2)
  assert_true("first owner detaches independently", markdown:detach())
  assert_true("shared attachment remains", shared:is_current())
  assert_true("Unicode surface remains for shared owner", require("math-conceal.render").is_attached(bufnr))
  shared:detach()

  set_source(bufnr, { "Formula: \\alpha + \\beta" })
  local latex = conceal.attach(bufnr, {
    source = {
      kind = "latex",
      filetype = "tex",
      path = "/tmp/math-conceal-attach.tex",
    },
    surfaces = { unicode = true, image = false },
    owner = "preview",
  })
  assert_eq("LaTeX logical source", conceal.get_attachment(bufnr).source.kind, "latex")
  assert_eq("LaTeX root parser", vim.treesitter.get_parser(bufnr, "latex"):lang(), "latex")
  assert_true("LaTeX conceal marks collected", #display_marks(bufnr) > 0)
  latex:detach()

  print("attach-api-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
