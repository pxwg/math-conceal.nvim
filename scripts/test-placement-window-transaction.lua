-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-placement-window-transaction.lua'

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local calls = { place = 0, delete = 0, batch = 0 }
  package.loaded["math-conceal.image.terminal"] = {
    batch = function(fn)
      calls.batch = calls.batch + 1
      return fn()
    end,
    place_image = function()
      calls.place = calls.place + 1
      return true
    end,
    delete_placement = function(_, placement_id)
      calls.delete = calls.delete + 1
      require("math-conceal.image.state").release_placement_id(placement_id)
    end,
  }

  local function assert_eq(label, actual, expected)
    if actual ~= expected then
      error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
    end
  end

  local function assert_true(label, value)
    if value ~= true then
      error(label, 2)
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "$x$ text",
    "",
    "$",
    "y",
    "$",
    "after",
  })
  vim.cmd("vsplit")
  local narrow = vim.api.nvim_get_current_win()
  local wide = nil
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= narrow and vim.api.nvim_win_get_buf(winid) == bufnr then
      wide = winid
      break
    end
  end
  assert_true("second split exists", wide ~= nil)
  vim.api.nvim_win_set_width(narrow, 12)

  local tracker = require("math-conceal.image.tracker")
  local inline_track = {
    bufnr = bufnr,
    tracker_generation = 1,
    track_id = 1,
    id = 1,
    state = "valid",
    row = 0,
    col = 0,
    end_row = 0,
    end_col = 3,
  }
  local block_track = {
    bufnr = bufnr,
    tracker_generation = 1,
    track_id = 2,
    id = 2,
    state = "valid",
    row = 2,
    col = 0,
    end_row = 4,
    end_col = 1,
  }
  local tracks = { [1] = inline_track, [2] = block_track }
  tracker.resolve_ref = function(ref)
    return ref and tracks[ref.track_id] or nil
  end
  tracker.source_line = function(requested_bufnr, row)
    return vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false)[1] or ""
  end

  local inline_key = tracker.track_ref_key(inline_track)
  local block_key = tracker.track_ref_key(block_track)
  local inline_request = {
    state = "ready",
    ref = vim.deepcopy(inline_track),
    realization_key = "inline",
    image_id = 401,
    natural_grid = { cols = 20, rows = 1 },
    display_kind = "inline",
    placement_style = { horizontal_align = "source", fit = {} },
  }
  local block_request = {
    state = "ready",
    ref = vim.deepcopy(block_track),
    realization_key = "block",
    image_id = 402,
    natural_grid = { cols = 20, rows = 2 },
    display_kind = "block",
    source_boundary_role = "isolated",
    placement_style = { horizontal_align = "center", fit = {} },
  }
  local transaction = {
    upsert = {
      [inline_key] = inline_request,
      [block_key] = block_request,
    },
  }
  vim.api.nvim_win_set_cursor(narrow, { 6, 0 })
  vim.api.nvim_win_set_cursor(wide, { 6, 0 })

  local placement = require("math-conceal.image.placement")
  assert_true("narrow transaction", placement.reconcile_window(narrow, transaction))
  assert_true("wide transaction", placement.reconcile_window(wide, transaction))
  local surfaces = placement._state().surface.surfaces_by_win
  assert_eq("inline keeps natural width", surfaces[narrow].records[inline_key].grid.cols, 20)
  assert_true(
    "narrow block fits less than wide block",
    surfaces[narrow].records[block_key].grid.cols < surfaces[wide].records[block_key].grid.cols
  )
  assert_eq("two records placed in each window", calls.place, 4)

  local calls_before_noop = calls.place
  assert_true("no-op transaction", placement.reconcile_window(narrow, {}))
  assert_eq("no-op does not place again", calls.place, calls_before_noop)

  vim.api.nvim_win_set_cursor(narrow, { 1, 1 })
  assert_true("cursor reveal transaction", placement.reconcile_window(narrow, {}))
  assert_true("narrow inline source visible", surfaces[narrow].records[inline_key].source_visible)
  assert_true("wide inline remains placed", surfaces[wide].records[inline_key].placed)
  local retained_id = surfaces[narrow].records[inline_key].placement_id
  assert_true("source reveal retains placement id", retained_id ~= nil)

  vim.api.nvim_win_set_cursor(narrow, { 6, 0 })
  assert_true("cursor restore transaction", placement.reconcile_window(narrow, {}))
  assert_eq("restore reuses placement id", surfaces[narrow].records[inline_key].placement_id, retained_id)

  assert_true("close transaction", placement.reconcile_window(narrow, { close = { [inline_key] = true } }))
  assert_eq("closed record removed", surfaces[narrow].records[inline_key], nil)
  assert_true("hard close deletes placement", calls.delete >= 1)

  placement.close_buffer(bufnr)
  print("placement-window-transaction-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
