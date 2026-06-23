-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-fold-grid-geometry-refresh.lua'

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

local function assert_false(label, value)
  if value then
    error(label, 2)
  end
end

local function run()
  add_repo_to_path()

  local terminal_calls = {}
  local delete_calls = {}
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
    delete_placement = function(image_id, placement_id)
      delete_calls[#delete_calls + 1] = {
        image_id = image_id,
        placement_id = placement_id,
      }
    end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "$",
    "x + y = z",
    "$",
    "",
    "",
    "",
  })
  vim.o.columns = 80
  vim.api.nvim_win_set_width(0, 80)

  local tracker = require("math-conceal.image.tracker")
  local placement = require("math-conceal.image.placement")

  local ref = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
  }
  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    row = 0,
    col = 0,
    end_row = 2,
    end_col = 1,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
    },
  }

  tracker.resolve_ref = function(requested_ref)
    return requested_ref and requested_ref.track_id == ref.track_id and track or nil
  end

  local asset = {
    image_id = 0x234567,
    cols = 12,
    rows = 3,
    render_key = "asset:move",
  }

  assert_true(
    "initial fold-grid sync succeeds",
    placement.sync(bufnr, {
      key = "math:moving",
      ref = ref,
      asset = asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  local surface = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()]
  assert_true("surface exists", surface ~= nil)
  local active = surface.placements["math:moving"]
  assert_true("placement exists", active ~= nil)
  assert_eq("initial image id", active.image_id, asset.image_id)
  local initial_placement_id = active.placement_id
  assert_eq("initial first carrier row", active.entries[1].source_start_row, 0)
  assert_eq("initial last carrier row", active.entries[#active.entries].source_end_row, 2)

  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "", "", "" })
  track.row = 3
  track.end_row = 5

  assert_true("geometry refresh reports movement", placement.refresh_geometry(bufnr))
  local moved = surface.placements["math:moving"]
  assert_true("moved placement still exists", moved ~= nil)
  assert_eq("geometry refresh preserves image id", moved.image_id, asset.image_id)
  assert_eq("geometry refresh preserves placement id", moved.placement_id, initial_placement_id)
  assert_eq("moved first carrier row", moved.entries[1].source_start_row, 3)
  assert_eq("moved last carrier row", moved.entries[#moved.entries].source_end_row, 5)
  assert_eq("geometry refresh does not delete placement", #delete_calls, 0)
  assert_true("geometry refresh re-places existing asset", #terminal_calls >= 2)
  assert_eq("last place uses existing image", terminal_calls[#terminal_calls].image_id, asset.image_id)
  assert_eq("last place uses existing placement", terminal_calls[#terminal_calls].placement_id, initial_placement_id)

  local place_count = #terminal_calls
  assert_false("unchanged geometry refresh is a no-op", placement.refresh_geometry(bufnr))
  assert_eq("unchanged refresh does not re-place image", #terminal_calls, place_count)

  placement.close_all(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("fold-grid-geometry-refresh-ok")
vim.cmd("qa!")
