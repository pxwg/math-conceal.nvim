-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-window-node-slot-repaint-gate.lua'

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

local function wait_scheduled()
  vim.cmd("redraw")
  vim.wait(80, function()
    return false
  end, 10)
end

local function run()
  add_repo_to_path()

  local terminal_calls = {}
  local batch_calls = 0
  package.loaded["math-conceal.image.terminal"] = {
    send_image = function(path, image_id)
      terminal_calls[#terminal_calls + 1] = { kind = "send_image", path = path, image_id = image_id }
      return true
    end,
    place_image = function(image_id, placement_id, cols, rows, opts)
      terminal_calls[#terminal_calls + 1] = {
        kind = "place_image",
        image_id = image_id,
        placement_id = placement_id,
        cols = cols,
        rows = rows,
        opts = opts,
      }
      return true
    end,
    delete_placement = function(image_id, placement_id)
      terminal_calls[#terminal_calls + 1] =
        { kind = "delete_placement", image_id = image_id, placement_id = placement_id }
    end,
    batch = function(fn)
      batch_calls = batch_calls + 1
      return fn()
    end,
  }

  local placement = require("math-conceal.image.placement")
  local tracker = require("math-conceal.image.tracker")

  local lines = {}
  for index = 1, 80 do
    lines[index] = "plain " .. index
  end
  lines[5] = "$"
  lines[6] = "x"
  lines[7] = "$"
  lines[35] = "$"
  lines[36] = "y"
  lines[37] = "$"

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.o.lines = 18
  vim.o.columns = 80
  vim.wo.wrap = true
  vim.wo.conceallevel = 2

  local tracks = {
    [1] = {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = 1,
      id = 1,
      kind = "typst",
      state = "valid",
      row = 4,
      col = 0,
      end_row = 6,
      end_col = 1,
      source_display_kind = "block",
      source_facts = { inline = false, isolated = true },
    },
    [2] = {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = 2,
      id = 2,
      kind = "typst",
      state = "valid",
      row = 34,
      col = 0,
      end_row = 36,
      end_col = 1,
      source_display_kind = "block",
      source_facts = { inline = false, isolated = true },
    },
  }
  tracker.source_line = function(requested_bufnr, row)
    return vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false)[1] or ""
  end
  tracker.resolve_ref = function(ref)
    return ref and tracks[ref.track_id] or nil
  end

  local function sync_track(track, image_id)
    return placement.sync(bufnr, {
      key = "track:" .. tostring(track.track_id),
      backend = "window_node_slot",
      ref = {
        bufnr = bufnr,
        tracker_generation = 1,
        generation = 1,
        track_id = track.track_id,
        id = track.id,
      },
      asset = {
        image_id = image_id,
        path = "/tmp/repaint-gate-" .. tostring(track.track_id) .. ".png",
        cols = 8,
        rows = 2,
        render_key = "asset:" .. tostring(track.track_id),
        uploaded = true,
      },
      display_role = "block",
      block_role = "isolated",
      align = "source",
      conceal_in_normal = true,
    })
  end

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert_true("visible track syncs", sync_track(tracks[1], 0x550001))
  assert_true("far track syncs", sync_track(tracks[2], 0x550002))
  terminal_calls = {}
  batch_calls = 0

  wait_scheduled()
  assert_eq("same viewport redraw does not repaint", #terminal_calls, 0)

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  wait_scheduled()
  assert_eq("cursor move in same viewport does not repaint", #terminal_calls, 0)

  vim.api.nvim_win_set_cursor(0, { 30, 0 })
  vim.cmd("normal! zt")
  wait_scheduled()
  local place_count = 0
  for _, call in ipairs(terminal_calls) do
    if call.kind == "place_image" then
      place_count = place_count + 1
    end
  end
  assert_true("viewport change repaints at least one visible placement", place_count > 0)
  assert_eq("viewport repaint uses one terminal batch", batch_calls, 1)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("window-node-slot-repaint-gate-ok")
vim.cmd("qa!")
