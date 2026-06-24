-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-fold-grid-asset-resize-sync.lua'

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
    image_id = 0x456789,
    cols = 12,
    rows = 2,
    render_key = "asset:resizable",
  }

  assert_true(
    "initial fold-grid sync succeeds",
    placement.sync(bufnr, {
      key = "math:resizable",
      ref = ref,
      asset = asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  local surface = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()]
  assert_true("surface exists", surface ~= nil)
  local active = surface.placements["math:resizable"]
  assert_true("placement exists", active ~= nil)
  local initial_placement_id = active.placement_id
  assert_eq("initial cols", active.cols, 12)
  assert_eq("initial rows", active.rows, 2)

  asset.cols = 7
  asset.rows = 3
  assert_true(
    "same image fold-grid sync succeeds after display resize",
    placement.sync(bufnr, {
      key = "math:resizable",
      ref = ref,
      asset = asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  local resized = surface.placements["math:resizable"]
  assert_true("resized placement exists", resized ~= nil)
  assert_eq("same image resize preserves placement id", resized.placement_id, initial_placement_id)
  assert_eq("active cols update from asset", resized.cols, 7)
  assert_eq("active rows update from asset", resized.rows, 3)
  assert_eq("resized row layout uses new row count", #resized.entries, 3)
  assert_eq("same image resize does not delete placement", #delete_calls, 0)
  assert_true("resize re-places existing asset", #terminal_calls >= 3)
  assert_eq("last place uses resized cols", terminal_calls[#terminal_calls].cols, 7)
  assert_eq("last place uses resized rows", terminal_calls[#terminal_calls].rows, 3)
  assert_eq("last place uses existing image", terminal_calls[#terminal_calls].image_id, asset.image_id)
  assert_eq("last place uses existing placement", terminal_calls[#terminal_calls].placement_id, initial_placement_id)

  placement.close_all(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("fold-grid-asset-resize-sync-ok")
vim.cmd("qa!")
