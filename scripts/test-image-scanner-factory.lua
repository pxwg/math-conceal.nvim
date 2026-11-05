-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-image-scanner-factory.lua

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("%s mismatch\nexpected: %s\nactual:   %s"):format(label, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function assert_error(label, pattern, fn)
  local ok, err = pcall(fn)
  if ok then
    error(label .. ": expected an error", 2)
  end
  if not tostring(err):find(pattern, 1, true) then
    error(("%s: error %q does not contain %q"):format(label, tostring(err), pattern), 2)
  end
end

local notifications = {}
vim.notify = function(message)
  notifications[#notifications + 1] = tostring(message)
end
vim.notify_once = vim.notify

package.loaded["math-conceal.image.projection"] = {
  detach = function() end,
  on_tracker_repair = function() end,
  on_layout_change = function() end,
  force_render = function() end,
  sync_cursor = function() end,
}
package.loaded["math-conceal.image.state"] = {
  refresh_cell_px_size = function()
    return false
  end,
}
package.loaded["math-conceal.image.capability"] = {
  assert_supported = function() end,
}

local image = require("math-conceal.image")
local tracker = require("math-conceal.image.tracker")
local typst = require("math-conceal.image.tracker.typst")

-- A factory scanner writes nodes in the documented schema itself.
local function block_node(bufnr, range)
  local source =
    table.concat(vim.api.nvim_buf_get_text(bufnr, range.row, range.col, range.end_row, range.end_col, {}), "\n")
  local rows = range.end_row - range.row + 1
  return {
    kind = "typst",
    source_kind = "typst",
    object_kind = "math",
    node_type = "math",
    row = range.row,
    col = range.col,
    end_row = range.end_row,
    end_col = range.end_col,
    source = source,
    source_hash = vim.fn.sha256(source),
    source_rows = rows,
    source_display_kind = "block",
    render_whole_line = true,
    source_facts = {
      source_kind = "typst",
      object_kind = "math",
      display_kind = "block",
      inline = false,
      isolated = true,
      break_line = rows > 1,
    },
    prelude_count = 0,
    prelude_signature = vim.fn.sha256(""),
  }
end

local function intersects(a, b)
  local function lt(ar, ac, br, bc)
    return ar < br or (ar == br and ac < bc)
  end
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

-- Minimal Org adapter: every #+begin_src typst body is one block node.
local function org_blocks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks, open = {}, nil
  for idx, line in ipairs(lines) do
    local row = idx - 1
    if open == nil and line:lower():match("^%s*#%+begin_src%s+typst") then
      open = row + 1
    elseif open ~= nil and line:lower():match("^%s*#%+end_src") then
      if row > open then
        blocks[#blocks + 1] = { row = open, col = 0, end_row = row - 1, end_col = #lines[row] }
      end
      open = nil
    end
  end
  return blocks
end

local factory_calls = {}
local function org_scanner(ctx)
  factory_calls[#factory_calls + 1] = ctx
  local function nodes(bufnr, window)
    local out = {}
    for _, range in ipairs(org_blocks(bufnr)) do
      if window == nil or intersects(range, window) then
        out[#out + 1] = block_node(bufnr, range)
      end
    end
    return out
  end
  return {
    scan_all = function(bufnr)
      return { nodes = nodes(bufnr), context_units = {}, context_signature = "" }
    end,
    scan_context = function()
      return { units = {}, signature = "" }
    end,
    scan = function(bufnr, window)
      return { nodes = nodes(bufnr, window), context_units = {} }
    end,
  }
end

local function renderer(scanner, extra)
  return {
    org_typst = vim.tbl_extend("force", {
      filetypes = { "org" },
      service_binary = "typst-concealer-service",
      source_kind = "typst",
      scanner = scanner,
      backend = "typst",
      wrapper = "typst",
    }, extra or {}),
  }
end

local function setup(renderers)
  image.setup({ enabled_by_default = false, styling_type = "none", renderers = renderers })
end

-- Spec validation fails at setup instead of at first attach.
assert_error("table scanner", "factory function", function()
  setup(renderer(org_scanner(nil)))
end)
assert_error("factory without source_kind", "explicit source_kind", function()
  setup(renderer(org_scanner, { source_kind = vim.NIL }))
end)
assert_error("unsupported factory source kind", 'got "markdown"', function()
  setup(renderer(org_scanner, { source_kind = "markdown" }))
end)
assert_error("unknown builtin", 'unknown builtin scanner "org"', function()
  setup(renderer("org"))
end)

-- Node construction helpers are internal.
assert_eq("no exported node helper", typst.node, nil)
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "x" })
assert_eq(
  "hand-written node validates",
  { typst._validate_node(block_node(scratch, { row = 0, col = 0, end_row = 0, end_col = 1 })) },
  { true }
)

-- Factory scanner on an Org buffer.
setup(renderer(org_scanner))
local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(bufnr, "/tmp/math-conceal-scanner-factory.org")
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  "* Heading",
  "#+begin_src typst",
  "$ sum_(k=1)^n k $",
  "#+end_src",
  "text",
  "#+BEGIN_SRC typst :exports results",
  "#set text(fill: red)",
  "Hello *Org*",
  "#+END_SRC",
})
vim.bo[bufnr].filetype = "org"
assert_eq("org buffer attaches", image.attach_buf(bufnr), true)
assert_eq("factory called once", #factory_calls, 1)
assert_eq("factory ctx", {
  factory_calls[1].kind,
  factory_calls[1].source_kind,
  factory_calls[1].scanner,
  factory_calls[1].filetype,
}, { "org_typst", "typst", "org_typst", "org" })
assert_eq("binding source kind", image.source_kind_for_bufnr(bufnr), "typst")
-- TrackView source_kind is the realization source kind, not the scanner name.
assert_eq("track view source kind", tracker.get_tracks(bufnr)[1].source_kind, "typst")

local function track_summary()
  local out = {}
  for _, track in ipairs(tracker.get_tracks(bufnr)) do
    out[#out + 1] = { track.row, track.end_row, track.source, track.source_display_kind, track.render_whole_line }
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  return out
end

assert_eq("initial tracks", track_summary(), {
  { 2, 2, "$ sum_(k=1)^n k $", "block", true },
  { 6, 7, "#set text(fill: red)\nHello *Org*", "block", true },
})

vim.api.nvim_buf_set_lines(bufnr, 7, 8, false, { "Hello *Org* again" })
tracker.repair(bufnr)
assert_eq("repaired tracks", track_summary(), {
  { 2, 2, "$ sum_(k=1)^n k $", "block", true },
  { 6, 7, "#set text(fill: red)\nHello *Org* again", "block", true },
})

-- Nodes outside the repair window would be born as duplicates; reject them.
local function sloppy_scanner(ctx)
  local inner = org_scanner(ctx)
  inner.scan = function(buf)
    return { nodes = inner.scan_all(buf).nodes }
  end
  return inner
end
image.disable_buf(bufnr)
setup(renderer(sloppy_scanner))
assert_eq("sloppy scanner attaches", image.attach_buf(bufnr), true)
notifications = {}
vim.api.nvim_buf_set_lines(bufnr, 7, 8, false, { "Hello *Org* once more" })
tracker.repair(bufnr)
assert_eq(
  "out-of-window node rejected",
  table.concat(notifications, "\n"):find("does not intersect the scan window", 1, true) ~= nil,
  true
)
image.disable_buf(bufnr)
setup(renderer(org_scanner))
factory_calls = {}
assert_eq("org buffer reattaches", image.attach_buf(bufnr), true)

assert_eq("same binding reuses scanner", image.attach_buf(bufnr), true)
assert_eq("factory not rerun for same binding", #factory_calls, 1)
image.disable_buf(bufnr)

-- Hand-written nodes that miss the schema fail loudly.
local function broken_scanner()
  return {
    scan_all = function()
      return { nodes = { { row = 2, col = 0, end_row = 2, end_col = 3, source = "abc" } } }
    end,
    scan_context = function()
      return { units = {}, signature = "" }
    end,
    scan = function()
      return { nodes = {} }
    end,
  }
end
setup(renderer(broken_scanner))
notifications = {}
image.attach_buf(bufnr)
local joined = table.concat(notifications, "\n")
assert_eq(
  "broken scanner reports schema error",
  joined:find("scan_all nodes[1] kind must be string", 1, true) ~= nil,
  true
)
assert_eq("broken scanner creates no tracks", #tracker.get_tracks(bufnr), 0)
image.disable_buf(bufnr)

-- Factory errors and missing methods disable the binding.
setup(renderer(function()
  return { scan = function() end }
end))
notifications = {}
assert_eq("missing scan_context rejects attach", image.attach_buf(bufnr), false)
assert_eq(
  "missing method message",
  table.concat(notifications, "\n"):find("missing scan_context()", 1, true) ~= nil,
  true
)
assert_eq("binding cleared", image.get_binding(bufnr), nil)

-- Builtin markdown scanner still receives renderer options.
if pcall(vim.treesitter.language.add, "markdown") and pcall(vim.treesitter.language.add, "markdown_inline") then
  image.setup({
    enabled_by_default = false,
    styling_type = "none",
    renderers = { markdown = { filetypes = { "markdown" }, backslash_math = true } },
  })
  local md = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(md)
  vim.api.nvim_buf_set_lines(md, 0, -1, false, { "$a$ and \\(b\\)" })
  vim.bo[md].filetype = "markdown"
  assert_eq("markdown attaches", image.attach_buf(md), true)
  assert_eq("markdown backslash option reaches builtin factory", #tracker.get_tracks(md), 2)
end

print("image scanner factory: OK")
