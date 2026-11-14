-- nvim --headless -u NONE -l scripts/test-environment-conceal.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local provider, render_ns
local set_provider = api.nvim_set_decoration_provider
api.nvim_set_decoration_provider = function(ns, callbacks)
  if api.nvim_get_namespaces()["math-conceal-render"] == ns then
    provider, render_ns = callbacks, ns
  else
    set_provider(ns, callbacks)
  end
end
local emitted = {}
local set_extmark = api.nvim_buf_set_extmark
api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
  if ns == render_ns and opts.ephemeral then
    emitted[#emitted + 1] = opts
    return 1
  end
  return set_extmark(buf, ns, row, col, opts)
end
require("math-conceal").setup({ image = { enabled = false }, integrations = { snacks = false } })
vim.treesitter.query.set("typst", "highlights", "(heading) @environment")
api.nvim_set_hl(0, "Normal", { fg = "#eeeeee" })
api.nvim_set_hl(0, "@environment.typst", { fg = "#ff8800" })
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
api.nvim_buf_set_lines(buf, 0, -1, false, { "= Heading $alpha$", "plain $alpha$", "cursor" })
local handle = require("math-conceal.nvim").attach(buf, {
  source = { kind = "typst", filetype = "typst" },
  surfaces = { unicode = true, image = false },
  owner = "test",
})
assert(handle.unicode)
vim.treesitter.get_parser(buf, "typst"):parse()
api.nvim_win_set_cursor(win, { 3, 0 })
provider.on_win(nil, win, buf, 0, 2)
local inherited, ordinary = false, false
for _, mark in ipairs(emitted) do
  if mark.conceal == "𝛼" then
    if mark.hl_group == "MathConcealEnvironmentFF8800" then
      inherited = true
    else
      ordinary = true
    end
  end
end
assert(inherited and ordinary, vim.inspect(emitted))
-- A stored decoration overrides the heading without changing any source text.
local ns = api.nvim_create_namespace("test-heading-decoration")
api.nvim_set_hl(0, "EnvironmentOverride", { fg = "#33aa55" })
set_extmark(buf, ns, 0, 0, { end_col = 17, hl_group = "EnvironmentOverride", priority = 200 })
emitted = {}
provider.on_win(nil, win, buf, 0, 2)
assert(
  vim.iter(emitted):any(function(mark)
    return mark.conceal == "𝛼" and mark.hl_group == "MathConcealEnvironment33AA55"
  end),
  vim.inspect(emitted)
)
-- A custom adapter disables lookup entirely, even with images disabled.
local root = require("math-conceal")
local runtime = require("math-conceal.nvim")
root.opts.image.renderers.org_typst = { source_kind = "typst", inherit_environment_color = false }
local function reattach()
  return runtime.attach(buf, {
    source = { kind = "typst", filetype = "typst", renderer = "org_typst" },
    surfaces = { unicode = true, image = false },
    owner = "test",
  })
end
local disabled = reattach()
assert(disabled.source.inherit_environment_color == false)
assert(
  runtime.resolve_source(buf, { kind = "typst", filetype = "typst", renderer = "typst" }).inherit_environment_color
)
local env = require("math-conceal.environment")
local resolve = env.resolve
env.resolve = function()
  error("disabled adapter must not resolve colors")
end
emitted = {}
provider.on_win(nil, win, buf, 0, 2)
assert(vim.iter(emitted):any(function(mark)
  return mark.conceal == "𝛼"
end))
assert(not vim.iter(emitted):any(function(mark)
  return (mark.hl_group or ""):find("MathConcealEnvironment", 1, true)
end))
env.resolve = resolve
root.opts.image.renderers.org_typst.inherit_environment_color = true
reattach()
emitted = {}
provider.on_win(nil, win, buf, 0, 2)
assert(vim.iter(emitted):any(function(mark)
  return mark.hl_group == "MathConcealEnvironment33AA55"
end))
print("environment-conceal-ok")
