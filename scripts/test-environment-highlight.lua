-- nvim --headless -u NONE -l scripts/test-environment-highlight.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local env = require("math-conceal.environment")
local api = vim.api
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
api.nvim_buf_set_lines(buf, 0, -1, false, { "heading $x$", "plain $x$" })
api.nvim_set_hl(0, "Normal", { fg = "#eeeeee" })
api.nvim_set_hl(0, "EnvironmentTitle", { fg = "#ff8800" })
api.nvim_set_hl(0, "EnvironmentBold", { bold = true })
local span = { bufnr = buf, row = 0, col = 8, end_row = 0, end_col = 11 }
local function eq(actual, expected)
  assert(actual == expected, vim.inspect({ actual = actual, expected = expected }))
end
local ns = api.nvim_create_namespace("test-environment")
local function mark(group, priority, namespace)
  return api.nvim_buf_set_extmark(
    buf,
    namespace or ns,
    0,
    0,
    { end_col = 11, hl_group = group, priority = priority or 100 }
  )
end
eq(env.resolve(buf, win, span), nil)
mark("EnvironmentTitle")
eq(env.resolve(buf, win, span), 0xff8800)
mark("EnvironmentBold", 150)
eq(env.resolve(buf, win, span), 0xff8800)
mark("Normal", 200)
eq(env.resolve(buf, win, span), nil)
api.nvim_buf_clear_namespace(buf, ns, 0, -1)
mark("EnvironmentTitle", 100, api.nvim_create_namespace("math-conceal-test"))
mark("EnvironmentTitle", 100, api.nvim_create_namespace("vim.diagnostic.test"))
eq(env.resolve(buf, win, span), nil)
vim.cmd([[syntax region EnvironmentTitle start=/heading/ end=/$/]])
eq(env.resolve(buf, win, span), 0xff8800)
vim.wo.winhighlight = "Normal:EnvironmentTitle"
eq(env.resolve(buf, win, span), nil)
vim.wo.winhighlight = ""
local window_ns = api.nvim_create_namespace("test-window-theme")
api.nvim_set_hl(window_ns, "EnvironmentTitle", { fg = "#33aa55" })
api.nvim_win_set_hl_ns(win, window_ns)
eq(env.resolve(buf, win, span), 0x33aa55)
api.nvim_win_set_hl_ns(win, 0)

local adapter = require("math-conceal.image.realization.typst")
local common = require("math-conceal.image.realization.common")
local ctx = { context_id = "test", context_rev = 1, context_units = {}, wrapper = "typst" }
local track = vim.tbl_extend("force", span, {
  track_id = 1,
  tracker_generation = 1,
  generation = 1,
  rev = 1,
  source = "$x$",
  source_hash = "x",
  object_kind = "math",
})
local layout = common.formula_layout(track, { winid = win }, {})
local desc = adapter.describe(track, ctx, layout, {}, "test")
assert(desc.node.source:find('#set text(fill: rgb("#FF8800"))', 1, true))
local original = adapter.describe(track, ctx, common.shared_layout(), {}, "test")
assert(original.key ~= desc.key and original.node.source_hash ~= desc.node.source_hash)
eq(common.formula_layout(track, { winid = win }, { inherit_environment = false }).key, "shared")
vim.cmd("syntax clear")
eq(common.formula_layout(track, { winid = win }, {}).key, "shared")
-- Real Tree-sitter captures: the string represents the formula range here.
api.nvim_buf_set_lines(buf, 0, -1, false, { 'local x = "math"' })
vim.treesitter.query.set(
  "lua",
  "highlights",
  [[
(chunk) @environment
(string) @formula
]]
)
api.nvim_set_hl(0, "@environment", { fg = "#ff8800" })
api.nvim_set_hl(0, "@formula.lua", { fg = "#ff0000" })
vim.treesitter.start(buf, "lua")
vim.treesitter.get_parser(buf, "lua"):parse()
local ts_span = { row = 0, col = 10, end_row = 0, end_col = 16 }
eq(env.resolve(buf, win, ts_span), 0xff8800)
-- Two windows can resolve the same source to different image layouts.
vim.cmd("vsplit")
local other = api.nvim_get_current_win()
local other_ns = api.nvim_create_namespace("test-other-window")
api.nvim_set_hl(other_ns, "@environment", { fg = "#33aa55" })
api.nvim_win_set_hl_ns(other, other_ns)
eq(env.resolve(buf, other, ts_span), 0x33aa55)
eq(env.resolve(buf, win, ts_span), 0xff8800)
local ts_track = vim.tbl_extend("force", track, ts_span)
assert(
  common.formula_layout(ts_track, { winid = other }, {}).key ~= common.formula_layout(ts_track, { winid = win }, {}).key
)
api.nvim_set_hl(0, "@environment", { fg = "#123456" })
eq(env.resolve(buf, win, ts_span), 0x123456)
vim.treesitter.stop(buf)
-- Shared policy used by images and live preview: renderer override wins.
eq(env.enabled({}, {}), true)
eq(env.enabled({}, { inherit_environment = false }), false)
eq(env.enabled({ inherit_environment_color = true }, { inherit_environment = false }), true)
local image = require("math-conceal.image")
local old_binding = image.get_binding
image.get_binding = function()
  return { inherit_environment_color = false }
end
local resolve = env.resolve
env.resolve = function()
  error("disabled image/preview lookup")
end
eq(env.resolve_for(buf, win, span, { inherit_environment_color = false }, {}), nil)
for _, name in ipairs({ "typst", "markdown" }) do
  eq(require("math-conceal.image.realization." .. name).layout(track, { winid = win }, ctx, {}).key, "shared")
end
env.resolve = resolve
image.get_binding = old_binding
-- Reattachment replaces bindings and clears stale preview/color state.
vim.treesitter.stop(buf)
api.nvim_buf_set_lines(buf, 0, -1, false, { "$ alpha $" })
image.setup({
  enabled_by_default = false,
  renderers = {
    custom = { filetypes = {}, source_kind = "typst", inherit_environment_color = false },
  },
})
local opts = { renderer = "custom", source = { kind = "typst", filetype = "typst" } }
assert(image.attach_buf(buf, opts))
local previous = image.get_binding(buf)
eq(previous.inherit_environment_color, false)
local state = require("math-conceal.image.state")
local previous_state = state.get_buf_state(buf)
previous_state.live_preview.render_key = "stale-color"
image.config.renderers.custom.inherit_environment_color = true
assert(image.attach_buf(buf, opts))
assert(image.get_binding(buf) ~= previous)
assert(state.get_buf_state(buf) ~= previous_state)
eq(image.get_binding(buf).inherit_environment_color, true)
assert(state.get_buf_state(buf).live_preview.render_key ~= "stale-color")
image.disable_buf(buf)
print("environment-highlight-ok")
