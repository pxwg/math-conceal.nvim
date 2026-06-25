-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-display-isolated-slot-lines.lua'

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
    delete = function() end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "  $",
    "  a",
    "  b",
    "  $",
    "after",
  })
  vim.cmd("set columns=80 lines=16 nowrap")

  local placement = require("math-conceal.image.placement")
  local state = require("math-conceal.image.state")
  local tracker = require("math-conceal.image.tracker")
  local formula_display = require("math-conceal.image.formula-display")

  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    row = 0,
    col = 2,
    end_row = 3,
    end_col = 3,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      break_line = true,
      isolated = true,
    },
  }

  tracker.get_tracks = function(requested_bufnr)
    return requested_bufnr == bufnr and { track } or {}
  end
  tracker.resolve_ref = function(ref)
    return ref and ref.track_id == track.track_id and track or nil
  end
  tracker.source_line = function(requested_bufnr, row)
    return (vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false) or { "" })[1] or ""
  end

  local key = tracker.track_ref_key(track)
  local function set_asset(rows)
    state.get_buf_state(bufnr).display_assets[key] = {
      asset = {
        image_id = 0x123456,
        cols = 3,
        rows = rows,
        render_key = "asset:" .. tostring(rows),
      },
    }
  end

  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  set_asset(2)
  formula_display.refresh(bufnr, { conceal_in_normal = false })
  local display_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.display_ns, 0, -1, { details = true })
  local aux_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.aux_ns, 0, -1, { details = true })
  assert_eq("window node slot creates no display extmarks", #display_marks, 0)
  assert_eq("window node slot creates no aux extmarks", #aux_marks, 0)

  local surface = placement._state().window_node_slot.surfaces_by_win[vim.api.nvim_get_current_win()]
  assert_true("window node slot surface exists", surface ~= nil)
  local active = surface.placements[key]
  assert_true("window node slot placement exists", active ~= nil)
  assert_eq("S>I keeps image-height carrier prefix", #active.carrier_rows, 2)
  assert_eq("S>I first carrier row", active.carrier_rows[1].row, 0)
  assert_eq("S>I second carrier row", active.carrier_rows[2].row, 1)
  assert_eq("S>I has no tail virt_lines", active.tail_count, 0)
  assert_eq("S>I preserves source fragment column", active.prefix_cols, 2)

  set_asset(5)
  formula_display.refresh(bufnr, { conceal_in_normal = false })
  surface = placement._state().window_node_slot.surfaces_by_win[vim.api.nvim_get_current_win()]
  active = surface.placements[key]
  assert_eq("S<I keeps all source rows as carriers", #active.carrier_rows, 4)
  assert_eq("S<I tail image rows are virt_lines", active.tail_count, 1)

  assert_true("window node slot places terminal image", #terminal_calls >= 2)
  formula_display.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-display-window-node-slot-lines-ok")
vim.cmd("qa!")
