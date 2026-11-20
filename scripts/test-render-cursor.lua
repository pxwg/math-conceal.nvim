-- Run with installed LaTeX parser:
--   nvim --headless -u NONE -i NONE -l scripts/test-render-cursor.lua

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(label .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual), 2)
  end
end

-- MATH_CONCEAL_LEGACY_CONCEAL=1 exercises the Neovim 0.12 ephemeral path on nightly.
if os.getenv("MATH_CONCEAL_LEGACY_CONCEAL") == "1" then
  vim.api.nvim__ns_set = nil
end

local function run()
  vim.opt.runtimepath:append(vim.fn.getcwd())
  assert(vim.treesitter.language.add("latex"), "LaTeX parser must be installed")

  local provider, redraws, emitted = nil, {}, {}
  local set_provider = vim.api.nvim_set_decoration_provider
  local set_extmark = vim.api.nvim_buf_set_extmark
  local render_ns = vim.api.nvim_create_namespace("math-conceal-render")
  vim.api.nvim_set_decoration_provider = function(ns, callbacks)
    if ns == render_ns then
      provider = callbacks
    else
      set_provider(ns, callbacks)
    end
  end
  vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
    if ns == render_ns and opts.ephemeral then
      emitted[#emitted + 1] = { row, col }
      return 0
    end
    return set_extmark(buf, ns, row, col, opts)
  end
  vim.api.nvim__redraw = function(opts)
    redraws[#redraws + 1] = opts
  end

  local render = require("math-conceal.render")
  local persistent = render.uses_persistent_conceal()
  render.setup({ conceal = {} }, "latex")
  render.update_query(
    "latex",
    [[
    ((generic_command) @symbol (#set! @symbol conceal "X"))
    ((displayed_equation) @equation (#set! @equation conceal "M"))
  ]]
  )

  local function attach(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "tex"
    assert(render.attach(buf, "latex"), "renderer attaches")
    return buf
  end

  local buf = attach({ "outside", "\\alpha and \\beta", "\\[", "a + b", "\\]", "outside again" })
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local function draw(target)
    target = target or vim.api.nvim_get_current_win()
    emitted = {}
    local owner = vim.api.nvim_win_get_buf(target)
    local last = vim.api.nvim_buf_line_count(owner) - 1
    -- Stand in for the native highlighter, which parses the viewport before our on_win.
    vim.treesitter.highlighter.active[owner].tree:parse({ 0, last + 1 })
    provider.on_win(nil, target, owner, 0, last)
  end
  local function event(name, pattern)
    vim.api.nvim_exec_autocmds(name or "CursorMoved", { pattern = pattern, modeline = false })
  end
  local function move(row, col, before_event)
    redraws = {}
    vim.api.nvim_win_set_cursor(0, { row, col })
    if before_event then
      draw()
    end
    event()
  end
  local function ranges()
    local out = {}
    for _, opts in ipairs(redraws) do
      -- Buffer-wide redraws come from the native highlighter's parse callbacks.
      if opts.win ~= nil or opts.buf == nil then
        assert_eq("redraw targets current window", opts.win, vim.api.nvim_get_current_win())
        assert_eq("redraw preserves valid screen lines", opts.valid, true)
        assert_eq("redraw batches flushing", opts.flush, false)
        out[#out + 1] = opts.range
      end
    end
    return out
  end
  -- Persistent surfaces hold the current conceal state; count it without drawing.
  local function surface_count(target)
    target = target or vim.api.nvim_get_current_win()
    local ns = render.window_namespace(target)
    if not ns then
      return 0
    end
    local count = 0
    for _, mark in
      ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(target), ns, 0, -1, { details = true }))
    do
      if mark[4].conceal ~= nil then
        count = count + 1
      end
    end
    return count
  end
  local function rendered(target)
    return persistent and surface_count(target) or #emitted
  end
  -- Legacy motion repaints toggled lines; persistent motion reconciles marks with no repaint.
  local function after_move(label, legacy_ranges, count)
    if persistent then
      assert_eq(label .. " (no repaint)", ranges(), {})
      assert_eq(label, surface_count(), count)
    else
      assert_eq(label, ranges(), legacy_ranges)
    end
  end

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  draw()
  event()
  assert_eq("all three concealed nodes render", rendered(), 3)
  move(1, 1)
  after_move("ordinary text needs no plugin redraw", {}, 3)

  move(2, 1)
  after_move("entering a symbol redraws its source line", { { 1, 2 } }, 2)
  draw()
  assert_eq("symbol under cursor expands", rendered(), 2)
  move(2, 2)
  after_move("moving within one symbol needs no redraw", {}, 2)
  move(2, 12)
  after_move("two toggles on one line coalesce", { { 1, 2 } }, 2)
  move(1, 0)
  draw()
  redraws = {}
  vim.api.nvim_win_set_cursor(win, { 2, 1 })
  event("CursorMovedI")
  after_move("insert-mode cursor motion reveals symbol", { { 1, 2 } }, 2)
  draw()
  move(1, 0)
  draw()

  -- :redraw can run on_win before CursorMoved. It must not consume the old
  -- cursor state: Neovim may only have repainted the old and new cursor lines.
  move(3, 1, true)
  after_move("early rendering preserves pending multiline reveal", { { 2, 5 } }, 2)
  draw()
  assert_eq("multiline equation expands", rendered(), 2)
  move(4, 2)
  after_move("motion within multiline equation needs no redraw", {}, 2)
  move(6, 0)
  after_move("leaving equation redraws all its source lines", { { 2, 5 } }, 3)
  draw()
  assert_eq("equation conceals again", rendered(), 3)

  vim.cmd("vsplit")
  local split = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(split, { 1, 0 })
  draw(split)
  event()
  move(2, 1)
  after_move("split redraw is local", { { 1, 2 } }, 2)
  vim.api.nvim_set_current_win(win)
  move(6, 1)
  after_move("other window retains independent cursor state", {}, 3)
  if persistent then
    assert_eq("split surface keeps its own reveal", surface_count(split), 2)
  end

  render.setup_buffer(buf, { mode = "preview" })
  draw()
  event()
  move(2, 1)
  after_move("preview motion never changes conceal", {}, 3)
  draw()
  assert_eq("preview retains symbol under cursor", rendered(), 3)

  move(4, 2)
  render.setup_buffer(buf, { mode = "edit" })
  draw()
  assert_eq("preview to edit expands multiline equation", rendered(), 2)
  move(6, 0, true)
  after_move("motion after mode redraw conceals the complete equation", { { 2, 5 } }, 3)
  render.setup_buffer(buf, { mode = "preview" })
  move(2, 1)
  draw()

  render.setup_buffer(buf, { mode = "presentation" })
  local get_mode = vim.api.nvim_get_mode
  local mode = "n"
  vim.api.nvim_get_mode = function()
    return { mode = mode, blocking = false }
  end
  draw()
  event()
  redraws = {}
  mode = "v"
  event("ModeChanged", "n:v")
  after_move("presentation visual entry reveals cursor node", { { 1, 2 } }, 2)
  draw()
  assert_eq("presentation visual selection expands symbol", rendered(), 2)
  redraws = {}
  mode = "n"
  event("ModeChanged", "v:n")
  after_move("presentation visual exit conceals cursor node", { { 1, 2 } }, 3)
  vim.api.nvim_get_mode = get_mode

  local replacement = attach({ "plain", "plain", "\\gamma", "plain" })
  vim.api.nvim_win_set_buf(win, replacement)
  vim.api.nvim_win_set_cursor(win, { 3, 1 })
  draw()
  redraws = {}
  event()
  after_move("reused window initializes replacement buffer cursor", {}, 0)
  move(1, 0)
  after_move("replacement redraw uses only replacement marks", { { 2, 3 } }, 1)

  vim.api.nvim_buf_set_lines(replacement, 2, 3, false, { "\\delta" })
  move(3, 1)
  -- The edit itself repaints; persistent surfaces rebuild rows of the new generation lazily.
  assert_eq("edit invalidation conservatively repaints viewport", ranges(), persistent and {} or { { 0, 4 } })
  draw()
  assert_eq("edited symbol under cursor expands", rendered(), 0)
  move(3, 2)
  after_move("refreshed edit cache restores no-op motion", {}, 0)
  move(1, 0)
  after_move("refreshed edit cache restores targeted redraw", { { 2, 3 } }, 1)

  vim.api.nvim_buf_set_lines(replacement, 0, -1, false, { "outside", "\\[", "a + b", "\\]", "outside" })
  vim.api.nvim_win_set_cursor(win, { 3, 1 })
  draw()
  event()
  vim.api.nvim_set_current_win(split)
  draw()
  event()
  vim.api.nvim_set_current_win(win)

  redraws = {}
  render.set_default_buffer_config({ mode = "preview" })
  assert_eq(
    "default change redraws only inheriting windows",
    vim.tbl_map(function(opts)
      return opts.win
    end, redraws),
    { win }
  )
  draw()
  assert_eq("default preview conceals equation under cursor", rendered(), 1)
  move(3, 2)
  render.set_default_buffer_config({ mode = "edit" })
  draw()
  assert_eq("default edit expands equation under cursor", rendered(), 0)
  move(5, 0, true)
  after_move("motion after default mode redraw conceals equation", { { 1, 4 } }, 1)
  assert_eq("explicit mode survives default changes", render.get_buffer_config(buf).mode, "presentation")
  vim.api.nvim_set_current_win(split)
  move(1, 0)
  after_move("default changes preserve explicit mode cursor state", {}, 3)

  render.detach(buf)
  render.detach(replacement)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
print("render-cursor-ok")
vim.cmd("qa!")
