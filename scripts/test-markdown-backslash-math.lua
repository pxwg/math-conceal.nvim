-- Run: nvim --headless -u NONE -i NONE -l scripts/test-markdown-backslash-math.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
local scanner = require("math-conceal.image.tracker.markdown")
local extension = "math-conceal.image.tracker.markdown_backslash"
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "$a$ and $$b$$",
  [=[\(c\)]=],
  [=[\[]=],
  "d",
  [=[\]]=],
  [=[`\(hidden\)`]=],
  "```text",
  [=[\[hidden\]]=],
  "```",
  [=[\\(escaped\\)]=],
  [=[\[unclosed]=],
})
local function check(result, expected)
  local found = {}
  for _, node in ipairs(result.nodes) do
    found[#found + 1] = node.source_facts.delimiter
  end
  assert(vim.deep_equal(found, expected), vim.inspect(found))
end
local dollars = { "dollar_inline", "dollar_block" }
check(scanner.scan_all(buf), dollars)
assert(package.loaded[extension] == nil, "default path loaded optional scanner")
local enabled = scanner.new({ backslash_math = true })
local disabled = scanner.new({ backslash_math = false })
check(enabled.scan_all(buf), { "dollar_inline", "dollar_block", "paren_inline", "bracket_block" })
check(disabled.scan_all(buf), dollars)
check(enabled.scan(buf, { row = 2, col = 0, end_row = 5, end_col = 0 }), { "bracket_block" })
-- Even after loading the extension, disabled scans must never invoke it.
package.loaded[extension].collect = function()
  error("disabled scanner invoked extension")
end
check(disabled.scan_all(buf), dollars)
check(disabled.scan(buf, { row = 0, col = 0, end_row = 11, end_col = 0 }), dollars)
vim.api.nvim_buf_delete(buf, { force = true })
print("markdown backslash math: OK")
