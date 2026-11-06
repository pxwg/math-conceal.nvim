-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-preview-injected-typst-span.lua

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")
local treesitter = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
if vim.fn.isdirectory(treesitter) == 1 then
  vim.opt.runtimepath:append(treesitter)
end

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("%s mismatch\nexpected: %s\nactual:   %s"):format(label, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

for _, lang in ipairs({ "markdown", "typst" }) do
  assert(pcall(vim.treesitter.language.add, lang), "missing Tree-sitter parser: " .. lang)
end

local preview = require("math-conceal.image.preview")

local function track(bufnr, row, source)
  return {
    bufnr = bufnr,
    row = row,
    col = 0,
    end_row = row,
    end_col = #source,
    source = source,
    node_type = "math",
    source_kind = "typst",
  }
end

-- Typst root buffer keeps the existing behavior.
local typ = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(typ, 0, -1, false, { "$ a + b $" })
vim.bo[typ].filetype = "typst"
local source, _, span = preview._highlighted_preview_source(track(typ, 0, "$ a + b $"), 0, 2, "n", "typst")
assert_eq("typst root span", span, { start_row = 0, start_col = 2, end_row = 0, end_col = 3 })
assert_eq("typst root preview source", source, "$ #text(red)[$a$]; + b $")

-- Typst injected into another host language.
local md = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(md, 0, -1, false, { "Intro", "", "```typst", "$ a + b $", "```" })
vim.bo[md].filetype = "markdown"
local host = vim.treesitter.get_parser(md, "markdown")
source, _, span = preview._highlighted_preview_source(track(md, 3, "$ a + b $"), 3, 6, "n", "markdown")
assert_eq("injected span", span, { start_row = 3, start_col = 6, end_row = 3, end_col = 7 })
assert_eq("injected preview source", source, "$ a + #text(red)[$b$]; $")
assert_eq("host parser is kept", vim.treesitter.get_parser(md) == host and host:lang(), "markdown")

-- Cursor outside any Typst tree yields no span.
local _, _, outside = preview._highlighted_preview_source(track(md, 0, "Intro"), 0, 1, "n", "markdown")
assert_eq("non-typst host text has no span", outside, nil)

print("preview-injected-typst-span-ok")
