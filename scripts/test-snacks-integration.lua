-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-snacks-integration.lua

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

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function marks(bufnr)
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

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(scratch)
  vim.bo[scratch].filetype = "snacks_picker_preview"
  vim.wo.conceallevel = 0
  vim.wo.concealcursor = ""

  local preview_calls = 0
  local function stock_file_preview(ctx)
    preview_calls = preview_calls + 1
    if ctx.item.buf and vim.api.nvim_buf_is_loaded(ctx.item.buf) then
      ctx.buf = ctx.item.buf
      return
    end

    ctx.buf = scratch
    vim.treesitter.stop(scratch)
    vim.api.nvim_buf_clear_namespace(scratch, -1, 0, -1)
    if ctx.item.file:match("%.typ$") then
      set_lines(scratch, { "$ alpha + beta $" })
      vim.treesitter.start(scratch, "typst")
    elseif ctx.item.file:match("%.md$") then
      set_lines(scratch, { "Inline $\\alpha + \\beta$." })
      vim.treesitter.start(scratch, "markdown")
    elseif ctx.item.file:match("%.tex$") then
      set_lines(scratch, { "Formula: \\alpha + \\beta" })
      vim.treesitter.start(scratch, "latex")
    else
      set_lines(scratch, { "unsupported" })
    end
  end

  local fake_snacks = {
    picker = {
      preview = { file = stock_file_preview },
      util = {
        path = function(item)
          return item.file
        end,
      },
    },
  }
  package.loaded.snacks = fake_snacks
  _G.Snacks = fake_snacks

  local close_calls = 0
  local picker = {
    opts = {
      cwd = "/tmp",
      previewers = { file = {} },
      on_close = function()
        close_calls = close_calls + 1
      end,
    },
  }
  local preview = { win = { buf = scratch } }
  local ctx = {
    picker = picker,
    preview = preview,
    buf = scratch,
    item = { file = "/tmp/math-conceal-snacks.typ" },
  }

  local conceal = require("math-conceal")
  conceal.setup({ image = { enabled = false } })
  assert_true("default Snacks adapter wraps stock file preview", fake_snacks.picker.preview.file ~= stock_file_preview)

  fake_snacks.picker.preview.file(ctx)
  local attached = conceal.get_attachment(scratch)
  assert_eq("Typst preview source", attached.source.kind, "typst")
  assert_eq("scratch preview uses presentation mode", attached.mode, "presentation")
  assert_true("Typst preview has conceal marks", #marks(scratch) > 0)
  assert_eq("preview window receives conceal options", vim.wo.conceallevel, 2)

  ctx.item = { file = "/tmp/math-conceal-snacks.md" }
  fake_snacks.picker.preview.file(ctx)
  attached = conceal.get_attachment(scratch)
  assert_eq("reused preview changes to Markdown source", attached.source.kind, "markdown")
  assert_true("Markdown preview has conceal marks", #marks(scratch) > 0)

  -- The fake stock preview deliberately resets the same buffer even for the
  -- same path. The adapter must notice the changedtick and refresh namespaces.
  fake_snacks.picker.preview.file(ctx)
  assert_eq("same-path reset keeps Markdown source", conceal.get_attachment(scratch).source.kind, "markdown")
  assert_true("same-path reset restores conceal marks", #marks(scratch) > 0)

  ctx.item = { file = "/tmp/math-conceal-snacks.tex" }
  fake_snacks.picker.preview.file(ctx)
  attached = conceal.get_attachment(scratch)
  assert_eq("LaTeX preview source", attached.source.kind, "latex")
  assert_true("LaTeX preview has conceal marks", #marks(scratch) > 0)

  ctx.item = { file = "/tmp/math-conceal-snacks.lua" }
  fake_snacks.picker.preview.file(ctx)
  assert_eq("unsupported preview detaches conceal", conceal.get_attachment(scratch), nil)
  assert_eq("unsupported preview restores conceal options", vim.wo.conceallevel, 0)

  local actual = vim.api.nvim_create_buf(false, true)
  local actual_path = "/tmp/math-conceal-snacks-loaded.typ"
  vim.api.nvim_buf_set_name(actual, actual_path)
  vim.bo[actual].filetype = "typst"
  set_lines(actual, { "$ alpha $" })
  conceal.set("typst", actual)
  assert_eq("loaded buffer begins with filetype owner", conceal.get_attachment(actual).owner_count, 1)

  ctx.item = { file = actual_path, buf = actual }
  ctx.buf = scratch
  fake_snacks.picker.preview.file(ctx)
  attached = conceal.get_attachment(actual)
  assert_eq("loaded preview keeps edit mode", attached.mode, "edit")
  assert_eq("loaded preview adds an independent owner", attached.owner_count, 2)

  picker.opts.on_close(picker)
  assert_eq("picker close preserves loaded buffer owner", conceal.get_attachment(actual).owner_count, 1)
  assert_eq("picker close calls prior on_close", close_calls, 1)
  conceal.detach(actual, { owner = "filetype" })

  local integration = require("math-conceal.integrations.snacks")
  local custom_picker = { opts = { cwd = "/tmp", previewers = { file = {} } } }
  local custom_ctx = {
    picker = custom_picker,
    preview = preview,
    buf = scratch,
    item = { file = "/tmp/custom-source.unknown" },
  }
  local custom = integration.wrap(function(inner)
    inner.buf = scratch
    set_lines(scratch, { "$ alpha $" })
  end, {
    source = function(_, _, source)
      source.kind = "typst"
      source.filetype = "typst"
      return source
    end,
    image = false,
  })
  custom(custom_ctx)
  assert_eq("custom wrapper source resolver", conceal.get_attachment(scratch).source.kind, "typst")
  integration.detach(custom_ctx)

  integration.teardown()
  assert_true("teardown restores stock previewer", fake_snacks.picker.preview.file == stock_file_preview)
  conceal.setup({ integrations = { snacks = false } })
  assert_true("disabled default adapter leaves stock previewer", fake_snacks.picker.preview.file == stock_file_preview)
  assert_true("stock preview was exercised", preview_calls >= 6)
  print("snacks-integration-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
