-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-fold-grid-foldtext-repaint.lua'

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

local function run()
  add_repo_to_path()

  local terminal_calls = {}
  package.loaded["math-conceal.image.terminal"] = {
    place_image = function(image_id, placement_id, cols, rows, opts)
      terminal_calls[#terminal_calls + 1] = {
        image_id = image_id,
        placement_id = placement_id,
        cols = cols,
        rows = rows,
        opts = opts,
      }
      return true
    end,
    delete_placement = function() end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "$",
    "a + b",
    "c + d",
    "$",
    "",
    "$",
    "x + y",
    "z + w",
    "$",
    "after",
  })
  vim.o.columns = 80
  vim.api.nvim_win_set_width(0, 80)

  local tracker = require("math-conceal.image.tracker")
  local placement = require("math-conceal.image.placement")

  local function make_ref(track_id)
    return {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = track_id,
      id = track_id,
    }
  end

  local function make_track(track_id, row, end_row)
    return {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = track_id,
      id = track_id,
      kind = "typst",
      state = "valid",
      row = row,
      col = 0,
      end_row = end_row,
      end_col = 1,
      source_display_kind = "block",
      source_facts = {
        inline = false,
        isolated = true,
      },
    }
  end

  local ref = make_ref(1)
  local other_ref = make_ref(2)
  local tracks = {
    [1] = make_track(1, 0, 3),
    [2] = make_track(2, 5, 8),
  }

  tracker.resolve_ref = function(requested_ref)
    return requested_ref and tracks[requested_ref.track_id] or nil
  end

  local asset = {
    image_id = 0x234567,
    cols = 12,
    rows = 2,
    render_key = "asset:foldtext-repaint",
  }
  local other_asset = {
    image_id = 0x234568,
    cols = 10,
    rows = 2,
    render_key = "asset:other",
  }

  assert_true(
    "initial fold-grid sync succeeds",
    placement.sync(bufnr, {
      key = "math:foldtext-repaint",
      ref = ref,
      asset = asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  assert_true(
    "second fold-grid sync succeeds",
    placement.sync(bufnr, {
      key = "math:other",
      ref = other_ref,
      asset = other_asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  local surface = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()]
  assert_true("surface exists", surface ~= nil)
  local active = surface.placements["math:foldtext-repaint"]
  assert_true("placement exists", active ~= nil)
  local other_active = surface.placements["math:other"]
  assert_true("other placement exists", other_active ~= nil)
  local placement_id = active.placement_id

  -- Let repaint work scheduled by initial fold setup drain before measuring the
  -- repaint caused by foldtext itself.
  vim.wait(100, function()
    return false
  end, 10)
  terminal_calls = {}

  assert_eq("second source row is folded", vim.fn.foldclosed(2), 2)
  vim.fn.foldtextresult(2)

  assert_true(
    "foldtext redraw schedules terminal repaint",
    vim.wait(200, function()
      return #terminal_calls > 0
    end, 10)
  )
  for _, call in ipairs(terminal_calls) do
    assert_eq("foldtext repaint targets only requested image", call.image_id, asset.image_id)
    assert_eq("foldtext repaint uses existing placement", call.placement_id, placement_id)
  end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("fold-grid-foldtext-repaint-ok")
vim.cmd("qa!")
