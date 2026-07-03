-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-bare-show-context.lua'

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

local function has_context_source(context_units, needle)
  for _, unit in ipairs(context_units or {}) do
    if (unit.source or ""):find(needle, 1, true) ~= nil then
      return true
    end
  end
  return false
end

local function create_typst_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "typst"
  vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test-bare-show-context.typ")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function run()
  add_repo_to_path()

  local image = require("math-conceal.image")
  local context = require("math-conceal.image.context")
  local tracker = require("math-conceal.image.tracker")
  local wrapper = require("math-conceal.image.wrapper")

  local bufnr = create_typst_buf({
    '#import "defs.typ": *',
    "#show: conf.with(",
    "  title: [TQFT],",
    ")",
    "#show math.equation: set text(size: 10pt)",
    '#let Ori = math.op("Ori")',
    "$sin(alpha)$",
  })

  assert_true("typst tracker attaches", tracker.attach(bufnr, { kind = "typst" }))

  local tracker_context = tracker.get_context(bufnr)
  assert_eq("context unit count excludes bare show", #tracker_context.units, 3)
  assert_true("import remains context", has_context_source(tracker_context.units, '#import "defs.typ": *'))
  assert_true("selector show remains context", has_context_source(tracker_context.units, "#show math.equation"))
  assert_true("let remains context", has_context_source(tracker_context.units, "#let Ori"))
  assert_true("bare show is not a context unit", not has_context_source(tracker_context.units, "conf.with"))
  assert_true("bare show title is not a context unit", not has_context_source(tracker_context.units, "title: [TQFT]"))

  local tracks = tracker.get_tracks(bufnr)
  assert_eq("single math track", #tracks, 1)
  assert_eq("math track prelude count excludes bare show", tracks[1].prelude_count, 3)

  local ctx = context.resolve(bufnr, {
    kind = "typst",
    source_kind = "typst",
    scanner = "typst",
    backend = "typst",
    wrapper = "typst",
    inputs = {},
    header = "",
  }, tracker_context, image.config)
  local slot_document = wrapper.build_slot_document(tracks[1], ctx, image.config)
  assert_true("render document omits bare show", not slot_document:find("conf.with", 1, true))
  assert_true("render document omits bare show title", not slot_document:find("title: [TQFT]", 1, true))
  assert_true("render document keeps selector show", slot_document:find("#show math.equation", 1, true) ~= nil)

  tracker.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-bare-show-context-ok")
vim.cmd("qa!")
