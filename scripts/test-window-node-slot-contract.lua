-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-window-node-slot-contract.lua'

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
    send_image = function(path, image_id)
      terminal_calls[#terminal_calls + 1] = {
        kind = "send_image",
        path = path,
        image_id = image_id,
      }
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
      terminal_calls[#terminal_calls + 1] = {
        kind = "delete_placement",
        image_id = image_id,
        placement_id = placement_id,
      }
    end,
  }

  local redraw_calls = {}
  local original_redraw = vim.api.nvim__redraw
  vim.api.nvim__redraw = function(opts)
    redraw_calls[#redraw_calls + 1] = vim.deepcopy(opts or {})
  end

  local function saw_forced_redraw(winid, start_row, end_row_exclusive, first_index)
    for index = first_index or 1, #redraw_calls do
      local opts = redraw_calls[index]
      if
        opts.win == winid
        and opts.valid == false
        and opts.flush == true
        and opts.range ~= nil
        and opts.range[1] == start_row
        and opts.range[2] == end_row_exclusive
      then
        return true
      end
    end
    return false
  end

  local function text_width(winid)
    local info = vim.fn.getwininfo(winid)[1] or {}
    return math.max(1, vim.api.nvim_win_get_width(winid) - (tonumber(info.textoff) or 0))
  end

  local placement = require("math-conceal.image.placement")
  local window_node_slot = require("math-conceal.image.placement.window-node-slot")
  local tracker = require("math-conceal.image.tracker")

  local count, height, tail = window_node_slot._choose_carrier_count({ 2, 2 }, 3)
  assert_eq("2+2 budget keeps one carrier", count, 1)
  assert_eq("2+2 budget carrier height", height, 2)
  assert_eq("2+2 budget adds one tail row", tail, 1)

  count, height, tail = window_node_slot._choose_carrier_count({ 5, 2 }, 3)
  assert_eq("oversize budget keeps one carrier", count, 1)
  assert_eq("oversize budget carrier height", height, 5)
  assert_eq("oversize budget has no tail", tail, 0)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "before",
    "  $",
    "  " .. string.rep("wide source wraps independently per window ", 5),
    "  $",
    "after",
    "  $",
    "  a",
    "  $",
    "done",
    "abcdefgh",
    "finished",
  })
  vim.o.columns = 100
  vim.o.lines = 24
  vim.wo.wrap = true
  vim.wo.conceallevel = 2
  vim.api.nvim_win_set_width(0, 38)
  local win_a = vim.api.nvim_get_current_win()

  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_b, bufnr)
  vim.wo[win_b].wrap = true
  vim.wo[win_b].conceallevel = 2
  vim.api.nvim_win_set_width(win_b, 58)

  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    row = 1,
    col = 2,
    end_row = 3,
    end_col = 3,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
    },
  }
  local short_track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 2,
    id = 2,
    kind = "typst",
    state = "valid",
    row = 5,
    col = 2,
    end_row = 7,
    end_col = 3,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
    },
  }
  local inline_virtual_track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 3,
    id = 3,
    kind = "typst",
    state = "valid",
    row = 9,
    col = 0,
    end_row = 9,
    end_col = 8,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
    },
  }
  local tracks_by_id = {
    [track.track_id] = track,
    [short_track.track_id] = short_track,
    [inline_virtual_track.track_id] = inline_virtual_track,
  }
  local source_line_calls = 0
  tracker.source_line = function(requested_bufnr, row)
    source_line_calls = source_line_calls + 1
    return vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false)[1] or ""
  end
  tracker.resolve_ref = function(ref)
    return ref and tracks_by_id[ref.track_id] or nil
  end

  local key = "track:window-node-slot"
  local intent = {
    key = key,
    backend = "window_node_slot",
    ref = {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = 1,
      id = 1,
    },
    asset = {
      image_id = 0x223344,
      path = "/tmp/window-node-slot-contract.png",
      cols = 12,
      rows = 3,
      render_key = "asset:window-node-slot",
    },
    display_role = "block",
    block_role = "isolated",
    align = "center",
    conceal_in_normal = false,
  }

  vim.api.nvim_win_set_cursor(win_a, { 1, 0 })
  vim.api.nvim_win_set_cursor(win_b, { 1, 0 })
  assert_true("window node slot sync succeeds", placement.sync(bufnr, intent))

  local state = placement._state().window_node_slot
  local surface_a = state.surfaces_by_win[win_a]
  local surface_b = state.surfaces_by_win[win_b]
  assert_true("surface A exists", surface_a ~= nil)
  assert_true("surface B exists", surface_b ~= nil)
  assert_true("surface namespaces differ", surface_a.ns ~= surface_b.ns)

  local active_a = surface_a.placements[key]
  local active_b = surface_b.placements[key]
  assert_true("placement A exists", active_a ~= nil and active_a.placed == true)
  assert_true("placement B exists", active_b ~= nil and active_b.placed == true)
  assert_true("window placement ids differ", active_a.placement_id ~= active_b.placement_id)
  assert_eq("image id is shared", active_a.image_id, active_b.image_id)
  assert_eq("window A centers image in local text area", active_a.prefix_cols, math.floor((text_width(win_a) - 12) / 2))
  assert_eq("window B centers image in local text area", active_b.prefix_cols, math.floor((text_width(win_b) - 12) / 2))
  assert_true("window node slot measures through tracker source lines", source_line_calls > 0)
  assert_true("window A materialize force-redraws source range", saw_forced_redraw(win_a, track.row, track.end_row + 1))
  assert_true("window B materialize force-redraws source range", saw_forced_redraw(win_b, track.row, track.end_row + 1))

  local redraw_count_before_noop = #redraw_calls
  local terminal_count_before_noop = #terminal_calls
  placement.refresh_geometry(bufnr, { keys = { [key] = true } })
  assert_eq("same-signature refresh does not force redraw", #redraw_calls, redraw_count_before_noop)
  assert_eq("same-signature refresh does not replace terminal placement", #terminal_calls, terminal_count_before_noop)

  local short_key = "track:window-node-slot-short"
  local short_intent = vim.deepcopy(intent)
  short_intent.key = short_key
  short_intent.ref.track_id = short_track.track_id
  short_intent.ref.id = short_track.id
  short_intent.asset.image_id = 0x223355
  short_intent.asset.path = "/tmp/window-node-slot-contract-short.png"
  short_intent.asset.render_key = "asset:window-node-slot-short"
  short_intent.align = "source"

  vim.api.nvim_buf_set_extmark(bufnr, surface_a.ns, short_track.row, 0, {
    virt_lines = {
      { { "orphan height contaminant", "" } },
      { { "orphan height contaminant", "" } },
      { { "orphan height contaminant", "" } },
    },
    priority = 999,
  })
  assert_true("short contaminated sync succeeds", placement.sync(bufnr, short_intent))
  local short_active_a = surface_a.placements[short_key]
  assert_eq("local remeasure clears orphan artifact before measuring", #short_active_a.carrier_rows, 3)
  assert_eq("local remeasure keeps delimiter raw height clean", short_active_a.carrier_rows[1].raw_height, 1)
  assert_eq("source-aligned slot preserves source fragment column", short_active_a.prefix_cols, 2)
  placement.close_key(bufnr, short_key)

  local inline_virtual_key = "track:window-node-slot-inline-virtual"
  local inline_virtual_intent = vim.deepcopy(intent)
  inline_virtual_intent.key = inline_virtual_key
  inline_virtual_intent.ref.track_id = inline_virtual_track.track_id
  inline_virtual_intent.ref.id = inline_virtual_track.id
  inline_virtual_intent.asset.image_id = 0x223366
  inline_virtual_intent.asset.path = "/tmp/window-node-slot-contract-inline-virtual.png"
  inline_virtual_intent.asset.rows = 2
  inline_virtual_intent.asset.render_key = "asset:window-node-slot-inline-virtual"
  inline_virtual_intent.align = "source"

  local external_ns = vim.api.nvim_create_namespace("window-node-slot-contract.external-inline")
  vim.api.nvim_buf_set_extmark(bufnr, external_ns, inline_virtual_track.row, 4, {
    virt_text = { { string.rep("x", text_width(win_a)), "" } },
    virt_text_pos = "inline",
  })
  local inline_oracle = vim.api.nvim_win_text_height(win_a, {
    start_row = inline_virtual_track.row,
    end_row = inline_virtual_track.row,
    start_vcol = 0,
  })
  assert_true("inline virtual text oracle wraps row", inline_oracle.all > 1)
  assert_true("inline virtual text sync succeeds", placement.sync(bufnr, inline_virtual_intent))
  local inline_active_a = surface_a.placements[inline_virtual_key]
  assert_eq(
    "window node slot consumes tracker-view oracle row height",
    inline_active_a.carrier_rows[1].raw_height,
    inline_oracle.all
  )
  assert_eq("oracle-height carrier consumes whole image", inline_active_a.tail_count, 0)
  placement.close_key(bufnr, inline_virtual_key)

  local initial_a_placement_id = active_a.placement_id
  intent.asset.cols = 7
  intent.asset.rows = 4
  intent.asset.render_key = "asset:window-node-slot:resized"
  local redraw_count_before_resize = #redraw_calls
  assert_true("same image resize sync succeeds", placement.sync(bufnr, intent))
  active_a = surface_a.placements[key]
  assert_eq("same image resize preserves window placement id", active_a.placement_id, initial_a_placement_id)
  assert_eq("same image resize updates cols", active_a.cols, 7)
  assert_eq("same image resize updates rows", active_a.rows, 4)
  assert_true(
    "resize materialize force-redraws source range",
    saw_forced_redraw(win_a, track.row, track.end_row + 1, redraw_count_before_resize + 1)
  )

  vim.api.nvim_win_set_cursor(win_a, { 3, 4 })
  vim.api.nvim_win_set_cursor(win_b, { 1, 0 })
  local redraw_count_before_reveal = #redraw_calls
  placement.refresh_geometry(bufnr, { keys = { [key] = true } })
  active_a = surface_a.placements[key]
  active_b = surface_b.placements[key]
  assert_eq("window A reveal clears placement", active_a.placed, false)
  assert_eq("window A reveal releases terminal placement", active_a.placement_id, nil)
  assert_eq("window B keeps placement visible", active_b.placed, true)
  assert_true(
    "source reveal deletes one terminal placement",
    terminal_calls[#terminal_calls].kind == "delete_placement"
  )
  assert_true(
    "source reveal force-redraws source range",
    saw_forced_redraw(win_a, track.row, track.end_row + 1, redraw_count_before_reveal + 1)
  )

  vim.api.nvim_win_set_cursor(win_a, { 1, 0 })
  placement.refresh_geometry(bufnr, { keys = { [key] = true } })
  active_a = surface_a.placements[key]
  assert_eq("window A restore places again", active_a.placed, true)
  assert_true("window A restore allocates placement id", active_a.placement_id ~= nil)

  placement.close_all(bufnr)
  vim.api.nvim__redraw = original_redraw
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("window-node-slot-contract-ok")
vim.cmd("qa!")
