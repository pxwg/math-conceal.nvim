-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-window-node-slot-repair-move-refresh.lua'

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

  local sync_calls = {}
  local refresh_geometry_calls = {}
  local reconcile_calls = {}
  local close_calls = {}
  package.loaded["math-conceal.image.placement"] = {
    available = function(name)
      return name == "window_node_slot"
    end,
    batch = function(fn)
      return fn()
    end,
    sync = function(bufnr, intent)
      sync_calls[#sync_calls + 1] = {
        bufnr = bufnr,
        intent = vim.deepcopy(intent),
      }
      return true
    end,
    close_key = function(bufnr, key)
      close_calls[#close_calls + 1] = { bufnr = bufnr, key = key }
    end,
    reconcile = function(bufnr, keys)
      reconcile_calls[#reconcile_calls + 1] = { bufnr = bufnr, keys = vim.deepcopy(keys or {}) }
    end,
    refresh_geometry = function(bufnr, opts)
      refresh_geometry_calls[#refresh_geometry_calls + 1] = {
        bufnr = bufnr,
        opts = vim.deepcopy(opts or {}),
      }
      return true
    end,
    close_all = function() end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "",
    "$",
    "this line is intentionally long enough to require window-local placement when wrap is enabled",
    "$",
    "",
  })
  vim.o.columns = 30
  vim.api.nvim_win_set_width(0, 30)
  vim.wo.wrap = true
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local tracker = require("math-conceal.image.tracker")
  local state = require("math-conceal.image.state")

  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    row = 1,
    col = 0,
    end_row = 3,
    end_col = 1,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
      break_line = true,
    },
  }

  tracker.source_line = function(requested_bufnr, row)
    return (vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false) or { "" })[1] or ""
  end
  tracker.get_tracks = function(requested_bufnr)
    return requested_bufnr == bufnr and { track } or {}
  end

  local key = tracker.track_ref_key(track)
  state.get_buf_state(bufnr).display_assets[key] = {
    asset = {
      image_id = 0x345678,
      cols = 12,
      rows = 3,
      render_key = "asset:window-node-slot",
    },
  }

  local formula_display = require("math-conceal.image.formula-display")

  formula_display.on_tracker_repair({
    bufnr = bufnr,
    initial = true,
    tracks = { track },
    retired_refs = {},
    context = { units = {}, changed_unit_indexes = {} },
  }, { conceal_in_normal = false })

  assert_eq("initial repair syncs placement once", #sync_calls, 1)
  assert_eq("initial intent backend", sync_calls[1].intent.backend, "window_node_slot")
  assert_eq("initial repair reconciles placement keys", #reconcile_calls, 1)
  assert_eq("initial repair does not need geometry-only refresh", #refresh_geometry_calls, 0)
  assert_eq("initial sync key", sync_calls[1].intent.key, key)

  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  track.row = 2
  track.end_row = 4

  formula_display.on_tracker_repair({
    bufnr = bufnr,
    tracks = { track },
    checked_refs = {},
    born_refs = {},
    retired_refs = {},
    identity_changed_refs = {},
    damage_ranges = { { row = 0, col = 0, end_row = 1, end_col = 0 } },
    repair_ranges = { { row = 0, col = 0, end_row = 1, end_col = 0 } },
    context = { units = {}, changed_unit_indexes = {} },
  }, { conceal_in_normal = false })

  assert_eq("geometry-only repair does not re-sync/recreate placement", #sync_calls, 1)
  assert_eq("geometry-only repair does not close placement", #close_calls, 0)
  assert_eq("geometry-only repair refreshes placement geometry", #refresh_geometry_calls, 1)
  assert_eq("geometry refresh bufnr", refresh_geometry_calls[1].bufnr, bufnr)
  assert_true("geometry refresh is targeted to window-node-slot key", refresh_geometry_calls[1].opts.keys[key] == true)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-window-node-slot-repair-move-refresh-ok")
vim.cmd("qa!")
