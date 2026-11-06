-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-typst-injection-scan.lua
-- Typst injected into a host filetype: Markdown fences are block regions,
-- markdown_inline latex blocks (re-injected as Typst) are inline regions.

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")
local treesitter = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
if vim.fn.isdirectory(treesitter) == 1 then
  vim.opt.runtimepath:append(treesitter)
end
for _, lang in ipairs({ "markdown", "markdown_inline", "typst" }) do
  assert(pcall(vim.treesitter.language.add, lang), "missing Tree-sitter parser: " .. lang)
end

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("%s mismatch\nexpected: %s\nactual:   %s"):format(label, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

vim.treesitter.language.register("markdown", "mdtypst")
local injections = {}
for _, file in ipairs(vim.treesitter.query.get_files("markdown_inline", "injections")) do
  injections[#injections + 1] = table.concat(vim.fn.readfile(file), "\n")
end
injections[#injections + 1] = [[
((latex_block) @injection.content
  (#set! injection.language "typst")
  (#set! injection.include-children))
]]
vim.treesitter.query.set("markdown_inline", "injections", table.concat(injections, "\n"))

local preview = require("math-conceal.image.preview")
local tracker = require("math-conceal.image.tracker")
local typst = require("math-conceal.image.tracker.typst")

local lines = {
  "Intro $a+b$ text", -- 0: inline region
  "",
  "```typst", -- 2: context-only block
  "#let f = 1",
  "```",
  "",
  "```typst", -- 6: markup block
  "sin alpha $f$",
  "#text(red)[$x$ hi]",
  "```",
  "",
  "```typst", -- 11: display math block
  "$ x^2 $",
  "```",
  "",
  "```typst", -- 15: inline math alone is markup
  "$y$",
  "```",
}

local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(bufnr, "/tmp/math-conceal-injection.md")
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
vim.bo[bufnr].filetype = "mdtypst"

local scanner = typst.new({ filetype = "mdtypst" })

local function summary(nodes)
  local out = {}
  for _, node in ipairs(nodes) do
    out[#out + 1] = {
      node.object_kind,
      { node.row, node.col, node.end_row, node.end_col },
      node.source,
      node.source_display_kind,
      node.source_facts.source_offset,
      node.prelude_count,
    }
  end
  return out
end

local scan = scanner.scan_all(bufnr)
assert_eq("scan_all nodes", summary(scan.nodes), {
  { "math", { 0, 6, 0, 11 }, "$a+b$", "inline", nil, 0 },
  { "code", { 6, 0, 9, 3 }, "sin alpha $f$\n#text(red)[$x$ hi]", "unknown", { rows = 1, col = 0 }, 1 },
  { "math", { 11, 0, 13, 3 }, "$ x^2 $", "block", { rows = 1, col = 0 }, 1 },
  { "code", { 15, 0, 17, 3 }, "$y$", "unknown", { rows = 1, col = 0 }, 1 },
})
assert_eq(
  "context shared across regions",
  vim.tbl_map(function(unit)
    return unit.source
  end, scan.context_units),
  { "#let f = 1" }
)
assert_eq("display math block is isolated", scan.nodes[3].source_facts.isolated, true)

-- A window on a delimiter line still finds the block.
assert_eq(
  "window on the opening delimiter",
  summary(scanner.scan(bufnr, { row = 6, col = 0, end_row = 6, end_col = 3 }, scan.context_units).nodes)[1][2],
  { 6, 0, 9, 3 }
)
assert_eq(
  "window between blocks",
  #scanner.scan(bufnr, { row = 10, col = 0, end_row = 10, end_col = 0 }, scan.context_units).nodes,
  0
)

-- Cursor-nested children of a markup block are its top-level units.
local nested = scanner.scan_nested(bufnr, scan.nodes[2], scan.context_units)
assert_eq("nested children", summary(nested.nodes), {
  { "math", { 7, 10, 7, 13 }, "$f$", "inline", nil, 1 },
  { "code", { 8, 0, 8, 18 }, "#text(red)[$x$ hi]", "unknown", nil, 1 },
})

-- Typst buffers keep scanning their root tree.
local typ = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(typ, 0, -1, false, { "#let g = 2", "$ a + b $" })
vim.bo[typ].filetype = "typst"
assert_eq("typst root scan", summary(typst.new({ filetype = "typst" }).scan_all(typ).nodes), {
  { "math", { 1, 0, 1, 9 }, "$ a + b $", "block", nil, 1 },
})

-- Tracker repair keeps one track per block across edits at the body end and
-- below the last body line.
assert(tracker.attach(bufnr, { kind = "typst", scanner = scanner }))
local function roots()
  local out = {}
  for _, track in ipairs(tracker.get_tracks(bufnr)) do
    if not track.cursor_nested then
      out[#out + 1] = { track.row, track.end_row, track.source }
    end
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  return out
end
local function edit(row, text_lines, replace)
  vim.api.nvim_buf_set_lines(bufnr, row, row + (replace and 1 or 0), false, text_lines)
  tracker.repair(bufnr)
end

edit(7, { "sin alpha $f$ gamma" }, true)
edit(9, { "$z$ more" })
assert_eq("one track per block after edits", roots(), {
  { 0, 0, "$a+b$" },
  { 6, 10, "sin alpha $f$ gamma\n#text(red)[$x$ hi]\n$z$ more" },
  { 12, 14, "$ x^2 $" },
  { 16, 18, "$y$" },
})

vim.api.nvim_win_set_cursor(0, { 8, 0 })
tracker.sync_cursor_nested(bufnr, { enabled = true })
local children = 0
for _, track in ipairs(tracker.get_tracks(bufnr)) do
  if track.cursor_nested then
    children = children + 1
  end
end
assert_eq("cursor in block creates nested tracks", children, 3)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
tracker.sync_cursor_nested(bufnr, { enabled = true })
assert_eq("leaving the block retires nested tracks", #roots(), #tracker.get_tracks(bufnr))

-- Preview highlighting slices from the source start, not the track start.
local math_block
for _, track in ipairs(tracker.get_tracks(bufnr)) do
  if track.row == 12 then
    math_block = vim.tbl_extend("force", track, { bufnr = bufnr })
  end
end
local source, _, span = preview._highlighted_preview_source(math_block, 13, 2, "n", "markdown")
assert_eq("block preview span", span ~= nil, true)
assert_eq("block preview source", source, "$ #text(red)[$x^2$]; $")
local plain = preview._highlighted_preview_source(math_block, 12, 1, "n", "markdown")
assert_eq("cursor on a delimiter keeps plain source", plain, "$ x^2 $")

tracker.detach(bufnr)
print("typst-injection-scan-ok")
