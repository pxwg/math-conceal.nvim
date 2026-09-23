-- Run with installed LaTeX parser:
--   nvim --headless -u NONE -i NONE -l scripts/test-render-cursor.lua

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(label .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual), 2)
  end
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
    provider.on_win(nil, target, owner, 0, vim.api.nvim_buf_line_count(owner) - 1)
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
      assert_eq("redraw targets current window", opts.win, vim.api.nvim_get_current_win())
      assert_eq("redraw preserves valid screen lines", opts.valid, true)
      assert_eq("redraw batches flushing", opts.flush, false)
      out[#out + 1] = opts.range
    end
    return out
  end

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  draw()
  event()
  assert_eq("all three concealed nodes render", #emitted, 3)
  move(1, 1)
  assert_eq("ordinary text needs no plugin redraw", ranges(), {})

  move(2, 1)
  assert_eq("entering a symbol redraws its source line", ranges(), { { 1, 2 } })
  draw()
  assert_eq("symbol under cursor expands", #emitted, 2)
  move(2, 2)
  assert_eq("moving within one symbol needs no redraw", ranges(), {})
  move(2, 12)
  assert_eq("two toggles on one line coalesce", ranges(), { { 1, 2 } })
  move(1, 0)
  draw()
  redraws = {}
  vim.api.nvim_win_set_cursor(win, { 2, 1 })
  event("CursorMovedI")
  assert_eq("insert-mode cursor motion reveals symbol", ranges(), { { 1, 2 } })
  draw()
  move(1, 0)
  draw()

  -- :redraw can run on_win before CursorMoved. It must not consume the old
  -- cursor state: Neovim may only have repainted the old and new cursor lines.
  move(3, 1, true)
  assert_eq("early rendering preserves pending multiline reveal", ranges(), { { 2, 5 } })
  draw()
  assert_eq("multiline equation expands", #emitted, 2)
  move(4, 2)
  assert_eq("motion within multiline equation needs no redraw", ranges(), {})
  move(6, 0)
  assert_eq("leaving equation redraws all its source lines", ranges(), { { 2, 5 } })
  draw()
  assert_eq("equation conceals again", #emitted, 3)

  vim.cmd("vsplit")
  local split = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(split, { 1, 0 })
  draw(split)
  event()
  move(2, 1)
  assert_eq("split redraw is local", ranges(), { { 1, 2 } })
  vim.api.nvim_set_current_win(win)
  move(6, 1)
  assert_eq("other window retains independent cursor state", ranges(), {})

  render.setup_buffer(buf, { mode = "preview" })
  draw()
  event()
  move(2, 1)
  assert_eq("preview motion never changes conceal", ranges(), {})
  draw()
  assert_eq("preview retains symbol under cursor", #emitted, 3)

  move(4, 2)
  render.setup_buffer(buf, { mode = "edit" })
  draw()
  assert_eq("preview to edit expands multiline equation", #emitted, 2)
  move(6, 0, true)
  assert_eq("motion after mode redraw conceals the complete equation", ranges(), { { 2, 5 } })
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
  assert_eq("presentation visual entry reveals cursor node", ranges(), { { 1, 2 } })
  draw()
  assert_eq("presentation visual selection expands symbol", #emitted, 2)
  redraws = {}
  mode = "n"
  event("ModeChanged", "v:n")
  assert_eq("presentation visual exit conceals cursor node", ranges(), { { 1, 2 } })
  vim.api.nvim_get_mode = get_mode

  local replacement = attach({ "plain", "plain", "\\gamma", "plain" })
  vim.api.nvim_win_set_buf(win, replacement)
  vim.api.nvim_win_set_cursor(win, { 3, 1 })
  draw()
  redraws = {}
  event()
  assert_eq("reused window initializes replacement buffer cursor", ranges(), {})
  move(1, 0)
  assert_eq("replacement redraw uses only replacement marks", ranges(), { { 2, 3 } })

  vim.api.nvim_buf_set_lines(replacement, 2, 3, false, { "\\delta" })
  move(3, 1)
  assert_eq("edit invalidation conservatively repaints viewport", ranges(), { { 0, 4 } })
  draw()
  assert_eq("edited symbol under cursor expands", #emitted, 0)
  move(3, 2)
  assert_eq("refreshed edit cache restores no-op motion", ranges(), {})
  move(1, 0)
  assert_eq("refreshed edit cache restores targeted redraw", ranges(), { { 2, 3 } })

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
  assert_eq("default preview conceals equation under cursor", #emitted, 1)
  move(3, 2)
  render.set_default_buffer_config({ mode = "edit" })
  draw()
  assert_eq("default edit expands equation under cursor", #emitted, 0)
  move(5, 0, true)
  assert_eq("motion after default mode redraw conceals equation", ranges(), { { 1, 4 } })
  assert_eq("explicit mode survives default changes", render.get_buffer_config(buf).mode, "presentation")
  vim.api.nvim_set_current_win(split)
  move(1, 0)
  assert_eq("default changes preserve explicit mode cursor state", ranges(), {})

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
