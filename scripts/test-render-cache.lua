-- Run with installed LaTeX, Typst, Markdown, and Markdown-inline parsers:
--   nvim --headless -u NONE -i NONE -l scripts/test-render-cache.lua

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(label .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual), 2)
  end
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function run()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  for _, lang in ipairs({ "latex", "typst", "markdown", "markdown_inline" }) do
    assert_true("Tree-sitter parser is installed for " .. lang, vim.treesitter.language.add(lang))
  end

  -- Use real parsers and queries; intercept only the screen boundary and count
  -- query passes. Ephemeral marks cannot be submitted outside a real redraw.
  local provider, render_ns
  local set_provider = vim.api.nvim_set_decoration_provider
  vim.api.nvim_set_decoration_provider = function(ns, callbacks)
    if vim.api.nvim_get_namespaces()["math-conceal-render"] == ns then
      provider, render_ns = callbacks, ns
    else
      set_provider(ns, callbacks)
    end
  end
  local emitted = {}
  local set_extmark = vim.api.nvim_buf_set_extmark
  vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
    if ns == render_ns and opts.ephemeral then
      emitted[#emitted + 1] = { row = row, col = col, conceal = opts.conceal, end_row = opts.end_row }
      return #emitted
    end
    return set_extmark(buf, ns, row, col, opts)
  end
  local passes = 0
  local query_ranges = {}
  local parsed = {}
  local parse = vim.treesitter.query.parse
  vim.treesitter.query.parse = function(...)
    local query = parse(...)
    if not parsed[query] then
      parsed[query] = true
      local iter_captures = query.iter_captures
      query.iter_captures = function(...)
        passes = passes + 1
        local first, last = select(4, ...)
        query_ranges[#query_ranges + 1] = { first, last }
        return iter_captures(...)
      end
    end
    return query
  end

  require("math-conceal").setup({ image = { enabled = false }, integrations = { snacks = false } })
  local conceal = require("math-conceal.nvim")
  local render = require("math-conceal.render")
  local function attach(kind, lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local handle = conceal.attach(buf, {
      source = { kind = kind, filetype = kind == "latex" and "tex" or kind },
      surfaces = { unicode = true, image = false },
      owner = "test",
    })
    assert_true(kind .. " attachment succeeds", handle.unicode)
    return buf, handle
  end
  local function draw(win, buf, top, bot)
    emitted = {}
    provider.on_win(nil, win, buf, top, bot)
    return emitted
  end
  local function has_symbol(marks, row, symbol)
    for _, mark in ipairs(marks) do
      if mark.row == row and mark.conceal == symbol then
        return true
      end
    end
    return false
  end
  local function assert_matches_fresh(label, target, owner, top, bot)
    local cached = render.collect_display_marks(owner, { winid = target, toprow = top, botrow = bot })
    local fresh = render.collect_display_marks(owner, { toprow = top, botrow = bot })
    assert_eq(label, cached, fresh)
    return cached
  end

  local source = { "Plain text without math." }
  for _ = 2, 320 do
    source[#source + 1] = string.rep("Wrapped prose ", 12) .. "$\\alpha + x^2$."
  end
  local buf, handle = attach("latex", source)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = true
  vim.wo[win].smoothscroll = true
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  local initial = draw(win, buf, 40, 50)
  assert_true("visible math is concealed", has_symbol(initial, 45, "α"))
  local cached_passes = passes
  assert_eq("unchanged redraw resubmits ephemeral marks", draw(win, buf, 40, 50), initial)
  assert_eq("unchanged redraw avoids queries", passes, cached_passes)
  assert_true("newly exposed row is concealed", has_symbol(draw(win, buf, 41, 51), 51, "α"))
  assert_eq("one-line scrolling reuses retained query results", passes, cached_passes)
  draw(win, buf, 39, 49)
  assert_eq("reversing direction reuses padding", passes, cached_passes)
  assert_true("last row of retained padding is concealed", has_symbol(draw(win, buf, 70, 80), 80, "α"))
  assert_eq("last retained row remains a cache hit", passes, cached_passes)

  -- A long source line can occupy many screen rows. The provider still receives
  -- source rows, so scrolling or resizing within the covered interval is a hit.
  vim.cmd("vsplit")
  local other_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 25)
  draw(win, buf, 40, 40)
  assert_eq("narrow wrapped viewport reuses source-position results", passes, cached_passes)
  vim.api.nvim_win_set_width(win, 45)
  draw(win, buf, 40, 48)
  assert_eq("resize within coverage does not requery", passes, cached_passes)

  draw(other_win, buf, 200, 210)
  cached_passes = passes
  draw(win, buf, 41, 51)
  draw(other_win, buf, 201, 211)
  assert_eq("two split viewports retain independent coverage", passes, cached_passes)
  draw(win, buf, 100, 110)
  assert_true("leaving coverage refills results", passes > cached_passes)
  cached_passes = passes
  assert_true("refilled padding contains new math", has_symbol(draw(win, buf, 101, 111), 111, "α"))
  assert_eq("refilled coverage is reusable", passes, cached_passes)

  local public = render.collect_display_marks(buf, { winid = win, toprow = 105, botrow = 105 })
  assert_true("public collection contains visible marks", #public > 0)
  for _, mark in ipairs(public) do
    assert_true("public collection excludes cached padding", mark.row <= 105 and mark.end_row >= 105)
  end
  local by_row = render.collect_display_marks_by_row(buf, { winid = win, toprow = 105, botrow = 105 })
  assert_eq("row collection exposes only requested rows", vim.tbl_keys(by_row), { 105 })
  assert_eq("row collection agrees with flat collection", by_row[105], public)
  assert_eq("public collection can reuse the window cache", passes, cached_passes)

  -- Query only uncovered source rows. Compare complete ordered marks against
  -- an independent exact-range collection after each refill.
  for _, case in ipairs({
    { name = "downward refill", top = 111, bot = 141, queries = { { 141, 172 } } },
    { name = "upward refill", top = 69, bot = 99, queries = { { 39, 81 } } },
    { name = "both-side growth", top = 30, bot = 140, queries = { { 0, 39 }, { 130, 171 } } },
    { name = "disjoint jump", top = 250, bot = 260, queries = { { 220, 291 } } },
  }) do
    query_ranges = {}
    draw(win, buf, case.top, case.bot)
    assert_eq(case.name .. " queries only missing rows", query_ranges, case.queries)
    assert_matches_fresh(case.name .. " preserves ordered marks", win, buf, case.top, case.bot)
  end

  vim.api.nvim_set_current_win(win)
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 105, 106, false, { "$\\alpha$" })
  vim.bo[buf].undolevels = 1000
  draw(win, buf, 100, 110)
  cached_passes = passes
  vim.api.nvim_buf_set_lines(buf, 105, 106, false, { "$\\beta$" })
  local edited = draw(win, buf, 100, 110)
  assert_true("edit invalidates cached query results", passes > cached_passes)
  assert_true("edited symbol is rendered", has_symbol(edited, 105, "β"))
  assert_true("old symbol disappears", not has_symbol(edited, 105, "α"))
  vim.cmd("silent undo")
  assert_true("undo restores symbols", has_symbol(draw(win, buf, 100, 110), 105, "α"))

  local replacement = {}
  for _ = 1, 320 do
    replacement[#replacement + 1] = "$\\gamma$"
  end
  local next_buf, next_handle = attach("latex", replacement)
  vim.api.nvim_win_set_buf(win, next_buf)
  local replaced = draw(win, next_buf, 100, 110)
  assert_true("reused window renders its new buffer", has_symbol(replaced, 105, "γ"))
  assert_true("reused window never leaks old symbols", not has_symbol(replaced, 105, "α"))
  handle:detach()
  cached_passes = passes
  assert_true("old buffer detach preserves replacement state", has_symbol(draw(win, next_buf, 101, 111), 105, "γ"))
  assert_eq("old buffer detach preserves replacement cache", passes, cached_passes)

  next_handle:refresh({ unicode = true, image = false })
  cached_passes = passes
  draw(win, next_buf, 100, 110)
  assert_true("explicit query refresh invalidates old cache", passes > cached_passes)
  next_handle:detach()

  for _, case in ipairs({
    { kind = "typst", text = "$ alpha + x^2 $", symbol = "𝛼" },
    { kind = "markdown", text = "Inline $\\alpha + x^2$.", symbol = "α" },
  }) do
    local lines = { "Ordinary prose." }
    for _ = 2, 100 do
      lines[#lines + 1] = case.text
    end
    local other_buf, other_handle = attach(case.kind, lines)
    vim.api.nvim_win_set_buf(win, other_buf)
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    assert_true(case.kind .. " produces Unicode marks", has_symbol(draw(win, other_buf, 40, 50), 45, case.symbol))
    cached_passes = passes
    assert_true(case.kind .. " retains offscreen symbols", has_symbol(draw(win, other_buf, 41, 51), 51, case.symbol))
    assert_eq(case.kind .. " reuses viewport padding", passes, cached_passes)
    for _, viewport in ipairs({ { 60, 90 }, { 0, 30 } }) do
      cached_passes = passes
      draw(win, other_buf, viewport[1], viewport[2])
      assert_true(case.kind .. " refills newly exposed rows", passes > cached_passes)
      assert_matches_fresh(case.kind .. " refill preserves ordered marks", win, other_buf, viewport[1], viewport[2])
    end
    other_handle:detach()
  end

  local last_buf, last_handle = attach("latex", { "Ordinary prose.", "$\\alpha$" })
  vim.api.nvim_win_set_buf(win, last_buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  assert_true("final source line is concealed", has_symbol(draw(win, last_buf, 0, 1), 1, "α"))
  assert_true(
    "single-row public collection includes the final source line",
    has_symbol(render.collect_display_marks(last_buf, { toprow = 1, botrow = 1 }), 1, "α")
  )
  last_handle:detach()

  local generation_buf, generation_handle = attach("latex", source)
  vim.api.nvim_win_set_buf(win, generation_buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  draw(win, generation_buf, 100, 110)
  local parser = vim.treesitter.get_parser(generation_buf, "latex")
  local changes = 0
  parser:register_cbs({
    on_changedtree = function()
      changes = changes + 1
    end,
  })
  local tick = vim.b[generation_buf].changedtick
  parser:set_included_regions({ { { 141, 0, 172, 0 } } })
  assert_eq("region change waits for parsing", changes, 0)
  local reparsed = draw(win, generation_buf, 111, 141)
  assert_true("refill parsing changes tree generation", changes > 0)
  assert_eq("parser generation changes without editing text", vim.b[generation_buf].changedtick, tick)
  assert_true("new parser region is concealed", has_symbol(reparsed, 141, "α"))
  assert_true("old cached parser region is discarded", not has_symbol(reparsed, 140, "α"))
  assert_matches_fresh("refill never merges different parser generations", win, generation_buf, 111, 141)
  for _, opts in ipairs({ { winid = win, toprow = 141, botrow = 150 }, { toprow = 141, botrow = 150 } }) do
    parser:set_included_regions({ { { 141, 0, 172, 0 } } })
    assert_true("parser region populates cache", #render.collect_display_marks(generation_buf, opts) > 0)
    parser:set_included_regions({ { { 200, 0, 231, 0 } } })
    assert_true("pending parser changes invalidate the tree", not parser:is_valid())
    assert_eq("cache hits reparse pending regions", render.collect_display_marks(generation_buf, opts), {})
  end
  generation_handle:detach()

  local parser_buf, parser_handle = attach("latex", vim.fn["repeat"]({ "$ alpha + x^2 $" }, 320))
  assert_true("replacement parser attaches", render.attach(parser_buf, "typst"))
  vim.api.nvim_win_set_buf(win, parser_buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  assert_true("replacement parser renders", has_symbol(draw(win, parser_buf, 100, 110), 100, "𝛼"))
  local range = { toprow = 100, botrow = 110 }
  assert_true("replacement parser populates range cache", #render.collect_display_marks(parser_buf, range) > 0)
  local replacement_parser = vim.treesitter.get_parser(parser_buf, "typst")
  replacement_parser:set_included_regions({ { { 141, 0, 172, 0 } } })
  replacement_parser:parse(true)
  assert_true("replacement parser finishes parsing", replacement_parser:is_valid())
  assert_eq("replacement parser invalidates viewport cache", draw(win, parser_buf, 100, 110), {})
  assert_eq("replacement parser invalidates range cache", render.collect_display_marks(parser_buf, range), {})
  parser_handle:detach()

  local multiline = {}
  for row = 0, 119 do
    multiline[#multiline + 1] = row == 9 and "\\frac{" or row == 89 and "}{2}" or "a"
  end
  local multiline_buf, multiline_handle = attach("latex", multiline)
  render.update_query("latex", '((curly_group) @test (#set! @test conceal "…"))')
  assert_true("custom multiline query attaches", render.attach(multiline_buf, "latex"))
  vim.api.nvim_win_set_buf(win, multiline_buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  local crossing = draw(win, multiline_buf, 40, 50)
  assert_true("capture starting before the cache margin is retained", has_symbol(crossing, 9, "…"))
  for _, mark in ipairs(crossing) do
    if mark.row == 9 then
      assert_eq("multiline capture retains its complete source range", mark.end_row, 89)
    end
  end
  cached_passes = passes
  assert_true(
    "scrolling into a multiline capture preserves conceal",
    has_symbol(draw(win, multiline_buf, 60, 70), 9, "…")
  )
  assert_eq("multiline cache hit avoids querying", passes, cached_passes)

  render.update_query(
    "latex",
    [[
    ((curly_group) @first (#set! @first conceal "A") (#set! @first priority 90))
    ((curly_group) @second (#set! @second conceal "B") (#set! @second priority 110))
  ]]
  )
  assert_true("distinct captures on one node attach", render.attach(multiline_buf, "latex"))
  draw(win, multiline_buf, 40, 50)
  local distinct = assert_matches_fresh("initial distinct captures retain order", win, multiline_buf, 40, 50)
  assert_eq("same node retains both capture priorities", { distinct[1].priority, distinct[2].priority }, { 90, 110 })
  for _, viewport in ipairs({ { 60, 90 }, { 0, 30 } }) do
    draw(win, multiline_buf, viewport[1], viewport[2])
    assert_matches_fresh(
      "multiline refill seam preserves distinct captures without duplicates",
      win,
      multiline_buf,
      viewport[1],
      viewport[2]
    )
  end
  multiline_handle:detach()

  local dense_buf, dense_handle = attach("latex", vim.fn["repeat"]({ "a" }, 40))
  render.update_query(
    "latex",
    [[
    ((text (word) @a (word) @b) (#set! @a conceal "X") (#set! @b conceal "Y"))
  ]]
  )
  assert_true("dense capture query attaches", render.attach(dense_buf, "latex"))
  vim.api.nvim_win_set_buf(win, dense_buf)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  draw(win, dense_buf, 0, 39)
  local dense = assert_matches_fresh("dense captures do not depend on queried range", win, dense_buf, 30, 30)
  assert_eq("dense query retains every capture on the requested row", #dense, 39)
  dense_handle:detach()

  print("render-cache-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
