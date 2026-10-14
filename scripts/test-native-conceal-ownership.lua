-- Run: nvim --headless -u NONE -i NONE -l scripts/test-native-conceal-ownership.lua
vim.opt.rtp:append(vim.fn.getcwd())
local ts = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
if vim.fn.isdirectory(ts) == 1 then
  vim.opt.rtp:append(ts)
end
-- Optional isolated parser/query runtime for remote QA.
if vim.env.MATH_CONCEAL_TEST_RUNTIME then
  vim.opt.rtp:prepend(vim.env.MATH_CONCEAL_TEST_RUNTIME)
end
require("math-conceal").setup({ ft = { "markdown" }, image = { enabled = false }, integrations = { snacks = false } })
local conceal = require("math-conceal.nvim")
local render = require("math-conceal.render")
local function newbuf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "[one](a) and [two](b)",
    "`code`",
    "$\\alpha + z$",
    "```text",
    "hello",
    "```",
  })
  return buf
end
local function captures(q, buf, lang)
  local parser = vim.treesitter.get_parser(buf, "markdown")
  parser:parse(true)
  local result = {}
  parser:for_each_tree(function(tree, lt)
    if lt:lang() == lang then
      for id, _, metadata in q:iter_captures(tree:root(), buf, 0, -1) do
        result[#result + 1] = { id = id, metadata = vim.deepcopy(metadata) }
      end
    end
  end)
  return result
end
local function has_conceal(rows)
  for _, row in ipairs(rows) do
    local m = row.metadata
    if m.conceal ~= nil or m.conceal_lines ~= nil then
      return true
    end
    for _, v in pairs(m) do
      if type(v) == "table" and (v.conceal ~= nil or v.conceal_lines ~= nil) then
        return true
      end
    end
  end
  return false
end
-- Programmatic overrides must be authoritative, including injected languages.
vim.treesitter.language.add("latex")
vim.treesitter.query.set(
  "latex",
  "highlights",
  [[
((word) @variable (#eq? @variable "z") (#set! @variable conceal "Z") (#set! @variable priority 123))
((generic_command) @function (#set! @function conceal "!") (#set! @function priority 999))
]]
)
local raw_latex = vim.treesitter.query.get("latex", "highlights")
local raw_inline = vim.treesitter.query.get("markdown_inline", "highlights")
local a, b = newbuf(), newbuf()
vim.api.nvim_set_current_buf(a)
vim.treesitter.start(a, "markdown")
vim.treesitter.start(b, "markdown")
local raw_before = captures(raw_inline, a, "markdown_inline")
assert(has_conceal(raw_before))
local handle = conceal.attach(a, { source = { kind = "markdown" }, owner = "qa" })
assert(handle.unicode)
assert(vim.treesitter.query.get("markdown_inline", "highlights") == raw_inline)
assert(vim.treesitter.query.get("latex", "highlights") == raw_latex)
local ah = vim.treesitter.highlighter.active[a]
local bh = vim.treesitter.highlighter.active[b]
assert(not has_conceal(captures(ah:get_query("markdown"):query(), a, "markdown")))
assert(ah:get_query("markdown"):query().has_conceal_line == false)
local unfiltered = captures(raw_inline, a, "markdown_inline")
local filtered = captures(ah:get_query("markdown_inline"):query(), a, "markdown_inline")
for _, row in ipairs(unfiltered) do
  row.metadata.conceal = nil
  row.metadata.conceal_lines = nil
  for key, data in pairs(row.metadata) do
    if type(key) == "number" and type(data) == "table" then
      data.conceal = nil
      data.conceal_lines = nil
    end
  end
end
assert(vim.deep_equal(unfiltered, filtered), "non-conceal metadata changed")

assert(not has_conceal(captures(ah:get_query("markdown_inline"):query(), a, "markdown_inline")))
assert(has_conceal(captures(bh:get_query("markdown_inline"):query(), b, "markdown_inline")))
assert(vim.deep_equal(raw_before, captures(raw_inline, a, "markdown_inline")), "shared metadata mutated")
local marks = render.collect_display_marks(a, { toprow = 0, botrow = 3 })
local link, code, greek, injected = 0, 0, 0, 0
for _, m in ipairs(marks) do
  if m.row == 0 then
    link = link + 1
  end
  if m.row == 1 then
    code = code + 1
  end
  if m.conceal == "α" then
    greek = greek + 1
  end
  assert(m.conceal ~= "!", "native rule overrides plugin math rule")
  if m.conceal == "Z" then
    injected = injected + 1
    assert(m.priority == 123)
  end
end
assert(link > 0 and code > 0 and greek == 1 and injected == 1, vim.inspect(marks))
-- Stop/start and detach must not leave filtered global queries behind.
vim.treesitter.stop(a)
vim.treesitter.start(a, "markdown")
local next_marks = render.collect_display_marks(a, { toprow = 0, botrow = 3 })
assert(vim.deep_equal(marks, next_marks), "restart changed marks")
handle:detach()
assert(
  has_conceal(captures(vim.treesitter.highlighter.active[a]:get_query("markdown_inline"):query(), a, "markdown_inline"))
)
-- Attach before highlighter startup.
local c = newbuf()
local early = conceal.attach(c, { source = { kind = "markdown" }, owner = "qa-early" })
assert(vim.treesitter.highlighter.active[c] == nil)
vim.treesitter.start(c, "markdown")
assert(
  not has_conceal(
    captures(vim.treesitter.highlighter.active[c]:get_query("markdown_inline"):query(), c, "markdown_inline")
  )
)
assert(#render.collect_display_marks(c, { toprow = 0, botrow = 3 }) > 4)
early:detach()
-- A highlighter-specific query takes precedence over the global effective query.
local d = newbuf()
local parser = vim.treesitter.get_parser(d, "markdown")
vim.treesitter.highlighter.new(
  parser,
  { queries = { markdown_inline = [[
((inline_link) @markup.link (#set! conceal "L") (#set! priority 125))
]] } }
)
local special = conceal.attach(d, { source = { kind = "markdown" }, owner = "qa-specific" })
local specific_marks = render.collect_display_marks(d, { toprow = 0, botrow = 3 })
local links = 0
for _, mark in ipairs(specific_marks) do
  if mark.row == 0 then
    assert(mark.conceal == "L" and mark.priority == 125)
    links = links + 1
  end
end
assert(links == 2, vim.inspect(specific_marks))
assert(vim.treesitter.query.get("markdown_inline", "highlights") == raw_inline)
special:detach()
-- Native-only configurations still attach and own all conceal.
render.update_query("latex", "")
local e = newbuf()
vim.treesitter.start(e, "markdown")
local only_native = conceal.attach(e, { source = { kind = "markdown" }, owner = "qa-native-only" })
assert(only_native.unicode)
assert(#render.collect_display_marks(e, { toprow = 0, botrow = 3 }) > 0)
only_native:detach()
for _, buf in ipairs({ a, b, c, d, e }) do
  vim.api.nvim_buf_delete(buf, { force = true })
end
print("native-conceal-ownership: OK")
