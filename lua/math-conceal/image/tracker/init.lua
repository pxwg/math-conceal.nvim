local debug_projection = require("math-conceal.image.tracker.debug")

local M = {}

local ns = vim.api.nvim_create_namespace("math-conceal.image.tracker")
local context_ns = vim.api.nvim_create_namespace("math-conceal.image.tracker.context")
local damage_ns = vim.api.nvim_create_namespace("math-conceal.image.tracker.damage")

---@type table<integer, table>
local state_by_buf = {}

---@type table<integer, integer>
local generation_by_buf = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function valid_loaded_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function le(a_row, a_col, b_row, b_col)
  return lt(a_row, a_col, b_row, b_col) or (a_row == b_row and a_col == b_col)
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function range_touches(a, b)
  return le(a.row, a.col, b.end_row, b.end_col) and le(b.row, b.col, a.end_row, a.end_col)
end

local function range_union(a, b)
  local row, col = a.row, a.col
  if lt(b.row, b.col, row, col) then
    row, col = b.row, b.col
  end

  local end_row, end_col = a.end_row, a.end_col
  if lt(end_row, end_col, b.end_row, b.end_col) then
    end_row, end_col = b.end_row, b.end_col
  end

  return { row = row, col = col, end_row = end_row, end_col = end_col }
end

local function resolve_scanner(kind, scanner)
  if scanner ~= nil then
    return scanner
  end

  if kind == "typst" then
    return require("math-conceal.image.tracker.typst")
  end
  if kind == "markdown" then
    return require("math-conceal.image.tracker.markdown")
  end

  return nil, "unsupported tracker kind: " .. tostring(kind)
end

local function notify_once(message, level)
  vim.notify_once("math-conceal image tracker: " .. message, level or vim.log.levels.WARN)
end

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function buf_end(bufnr)
  local last = vim.api.nvim_buf_line_count(bufnr) - 1
  return last, line_len(bufnr, last)
end

local function clamp_range(bufnr, row, col, end_row, end_col)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return 0, 0, 0, 0
  end

  row = math.max(0, math.min(row, line_count - 1))
  end_row = math.max(row, math.min(end_row, line_count - 1))
  col = math.max(0, math.min(col, line_len(bufnr, row)))
  end_col = math.max(0, math.min(end_col, line_len(bufnr, end_row)))
  if row == end_row and end_col < col then
    end_col = col
  end
  return row, col, end_row, end_col
end

local function materialize_damage(bufnr, damage)
  local row, col, end_row, end_col = clamp_range(bufnr, damage.row, damage.col, damage.end_row, damage.end_col)
  vim.api.nvim_buf_set_extmark(bufnr, damage_ns, row, col, {
    end_row = end_row,
    end_col = end_col,
    right_gravity = false,
    end_right_gravity = true,
    undo_restore = false,
    priority = 140,
  })
end

local function current_damage_ranges(bufnr)
  local ranges = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, damage_ns, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    local row, col, details = mark[2], mark[3], mark[4] or {}
    if row ~= nil and details.invalid ~= true then
      ranges[#ranges + 1] = {
        row = row,
        col = col,
        end_row = details.end_row or row,
        end_col = details.end_col or col,
      }
    end
  end
  return ranges
end

local function clear_damage(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, damage_ns, 0, -1)
end

local function line_damage_from_on_lines(bufnr, firstline, new_lastline)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return { row = 0, col = 0, end_row = 0, end_col = 0 }
  end

  local row = math.max(0, math.min(firstline or 0, line_count - 1))
  if new_lastline ~= nil and new_lastline > (firstline or 0) then
    local end_row = math.max(row, math.min(new_lastline - 1, line_count - 1))
    return { row = row, col = 0, end_row = end_row, end_col = line_len(bufnr, end_row) }
  end

  return { row = row, col = 0, end_row = row, end_col = 0 }
end

local function byte_at(bufnr, row, col)
  return vim.api.nvim_buf_get_offset(bufnr, row) + col
end

local function overlap_bytes(bufnr, track, node)
  local start_byte = math.max(byte_at(bufnr, track.row, track.col), byte_at(bufnr, node.row, node.col))
  local end_byte = math.min(byte_at(bufnr, track.end_row, track.end_col), byte_at(bufnr, node.end_row, node.end_col))
  return math.max(0, end_byte - start_byte)
end

local function track_snapshot(state, track)
  return {
    bufnr = state.bufnr,
    tracker_generation = state.generation,
    generation = state.generation,
    anchor_ns = ns,
    anchor_id = track.id,
    id = track.id,
    track_id = track.id,
    rev = track.rev,
    state = track.state,
    invalid = track.invalid == true,
    kind = state.kind,
    node_type = track.node_type,
    row = track.row,
    col = track.col,
    end_row = track.end_row,
    end_col = track.end_col,
    source = track.source,
    source_hash = track.source_hash,
    source_rows = track.source_rows,
    source_display_kind = track.source_display_kind,
    source_facts = vim.deepcopy(track.source_facts or {}),
    render_whole_line = track.render_whole_line == true,
    prelude_count = track.prelude_count or 0,
    prelude_signature = track.prelude_signature,
  }
end

local function track_ref(state, track)
  return {
    bufnr = state.bufnr,
    tracker_generation = state.generation,
    generation = state.generation,
    track_id = track.id,
    id = track.id,
  }
end

local function sorted_tracks(state, predicate)
  local tracks = {}
  for _, track in pairs(state.tracks) do
    if predicate == nil or predicate(track) then
      tracks[#tracks + 1] = track
    end
  end

  table.sort(tracks, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return a.id < b.id
  end)

  return tracks
end

local function live_tracks(state)
  return sorted_tracks(state, function(track)
    return track.state ~= "retired"
  end)
end

local function dirty_tracks(state)
  return sorted_tracks(state, function(track)
    return track.state == "dirty"
  end)
end

local function track_snapshots(state)
  local snapshots = {}
  for _, track in ipairs(live_tracks(state)) do
    snapshots[#snapshots + 1] = track_snapshot(state, track)
  end
  return snapshots
end

local function refresh_debug(state)
  if state == nil then
    return
  end

  if state.debug_enabled then
    debug_projection.refresh(state.bufnr, track_snapshots(state), { enabled = true })
  else
    debug_projection.clear(state.bufnr)
  end
end

local function snapshots_by_key(snapshots)
  local by_key = {}
  for _, snapshot in ipairs(snapshots or {}) do
    by_key[M.track_ref_key(snapshot)] = snapshot
  end
  return by_key
end

local function refs_from_keys(by_key, keys)
  local refs = {}
  table.sort(keys)
  for _, key in ipairs(keys) do
    local snapshot = by_key[key]
    if snapshot ~= nil then
      refs[#refs + 1] = {
        bufnr = snapshot.bufnr,
        tracker_generation = snapshot.tracker_generation,
        generation = snapshot.generation,
        track_id = snapshot.track_id,
        id = snapshot.track_id,
      }
    end
  end
  return refs
end

local function changed_context_indexes(old_units, new_units)
  old_units = old_units or {}
  new_units = new_units or {}
  local changed = {}
  local max_len = math.max(#old_units, #new_units)
  for idx = 1, max_len do
    local old_sig = old_units[idx] and old_units[idx].signature or nil
    local new_sig = new_units[idx] and new_units[idx].signature or nil
    if old_sig ~= new_sig then
      changed[#changed + 1] = idx
    end
  end
  return changed
end

local function min_value(values)
  local min = nil
  for _, value in ipairs(values or {}) do
    if min == nil or value < min then
      min = value
    end
  end
  return min
end

local function prefix_signatures(context_units)
  local signatures = { [0] = vim.fn.sha256("") }
  local parts = {}
  for idx, unit in ipairs(context_units or {}) do
    parts[#parts + 1] = unit.signature or ""
    signatures[idx] = vim.fn.sha256(table.concat(parts, "\0"))
  end
  return signatures
end

local function prelude_count_for_track(context_units, track)
  local count = 0
  for idx, unit in ipairs(context_units or {}) do
    if le(unit.end_row, unit.end_col, track.row, track.col) then
      count = idx
    else
      break
    end
  end
  return count
end

local function apply_context_to_tracks(state)
  local prefixes = prefix_signatures(state.context_units or {})
  for _, track in ipairs(live_tracks(state)) do
    local prelude_count = prelude_count_for_track(state.context_units, track)
    track.prelude_count = prelude_count
    track.prelude_signature = prefixes[prelude_count] or prefixes[0]
  end
end

local function set_context_extmark(bufnr, unit)
  if unit.index == nil then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, context_ns, unit.row, unit.col, {
    id = unit.index,
    end_row = unit.end_row,
    end_col = unit.end_col,
    right_gravity = true,
    end_right_gravity = false,
    undo_restore = true,
    invalidate = true,
    priority = 149,
  })
end

local function refresh_context_extmarks(bufnr, state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, context_ns, 0, -1)
  for idx, unit in ipairs(state.context_units or {}) do
    unit.index = idx
    set_context_extmark(bufnr, unit)
  end
end

local function sync_context_units(bufnr, state)
  local invalid = false
  for _, unit in ipairs(state.context_units or {}) do
    if unit.index ~= nil then
      local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, context_ns, unit.index, { details = true })
      local row, col, details = pos[1], pos[2], pos[3]
      if row == nil or details.invalid == true then
        invalid = true
      else
        unit.row = row
        unit.col = col
        unit.end_row = details.end_row or row
        unit.end_col = details.end_col or col
      end
    end
  end
  return invalid
end

local function diff_event(state, before_snapshots, after_snapshots, old_context_units, new_context_units, opts)
  opts = opts or {}
  local before = snapshots_by_key(before_snapshots)
  local after = snapshots_by_key(after_snapshots)
  local changed_keys = {}
  local retired_keys = {}
  local affected = {}

  for key, snapshot in pairs(after) do
    if before[key] == nil or not vim.deep_equal(before[key], snapshot) then
      changed_keys[#changed_keys + 1] = key
      affected[key] = snapshot
    end
  end

  for key, snapshot in pairs(before) do
    if after[key] == nil then
      retired_keys[#retired_keys + 1] = key
      affected[key] = snapshot
    end
  end

  local changed_units = changed_context_indexes(old_context_units, new_context_units)
  local first_changed_context = min_value(changed_units)
  if first_changed_context ~= nil then
    for key, snapshot in pairs(after) do
      if (snapshot.prelude_count or 0) >= first_changed_context then
        affected[key] = snapshot
      end
    end
  end

  local affected_keys = {}
  for key, _ in pairs(affected) do
    affected_keys[#affected_keys + 1] = key
  end

  state.repair_tick = (state.repair_tick or 0) + 1

  return {
    bufnr = state.bufnr,
    generation = state.generation,
    tracker_generation = state.generation,
    tick = state.repair_tick,
    initial = opts.initial == true,
    tracks = after_snapshots,
    changed_refs = refs_from_keys(after, changed_keys),
    retired_refs = refs_from_keys(before, retired_keys),
    affected_refs = refs_from_keys(vim.tbl_extend("force", before, after), affected_keys),
    context = {
      changed = first_changed_context ~= nil,
      signature = state.context_signature or "",
      changed_unit_indexes = changed_units,
      units = vim.deepcopy(state.context_units or {}),
    },
  }
end

local function emit_repair(state, event)
  refresh_debug(state)
  if type(state.on_repair) == "function" then
    local ok, err = pcall(state.on_repair, event)
    if not ok then
      notify_once("repair subscriber failed: " .. tostring(err), vim.log.levels.WARN)
    end
  end
end

local function set_core_extmark(bufnr, track)
  vim.api.nvim_buf_set_extmark(bufnr, ns, track.row, track.col, {
    id = track.id,
    end_row = track.end_row,
    end_col = track.end_col,
    right_gravity = true,
    end_right_gravity = false,
    undo_restore = true,
    invalidate = true,
    priority = 150,
  })
end

local function new_track(state, node)
  local id = state.next_track_id
  state.next_track_id = state.next_track_id + 1

  return {
    id = id,
    rev = 0,
    state = "valid",
    invalid = false,
    row = node.row,
    col = node.col,
    end_row = node.end_row,
    end_col = node.end_col,
    source = node.source,
    source_hash = node.source_hash,
    source_rows = node.source_rows,
    source_display_kind = node.source_display_kind,
    source_facts = vim.deepcopy(node.source_facts or {}),
    render_whole_line = node.render_whole_line == true,
    prelude_count = node.prelude_count or 0,
    prelude_signature = node.prelude_signature,
    node_type = node.node_type,
  }
end

local function retire(bufnr, track)
  track.state = "retired"
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, track.id)
end

local function mark_track_dirty_once(track)
  if track.state == "retired" then
    return
  end
  if track.state ~= "dirty" then
    track.rev = track.rev + 1
  end
  track.state = "dirty"
end

local function sync_track(bufnr, track)
  if track.state == "retired" then
    return
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, track.id, { details = true })
  local row, col, details = pos[1], pos[2], pos[3]
  if row == nil then
    mark_track_dirty_once(track)
    track.invalid = true
    return
  end

  track.row = row
  track.col = col
  track.end_row = details.end_row or row
  track.end_col = details.end_col or col
  track.invalid = details.invalid == true
  if track.invalid then
    mark_track_dirty_once(track)
  end
end

local function sync_tracks(bufnr, state)
  for _, track in pairs(state.tracks) do
    sync_track(bufnr, track)
  end
end

local function has_dirty_track(state)
  for _, track in pairs(state.tracks) do
    if track.state == "dirty" then
      return true
    end
  end
  return false
end

local function has_repair_geometry(damage_ranges, state)
  return #damage_ranges > 0 or has_dirty_track(state)
end

local function track_range(track)
  return { row = track.row, col = track.col, end_row = track.end_row, end_col = track.end_col }
end

local function merge_touching_ranges(ranges)
  table.sort(ranges, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return lt(a.end_row, a.end_col, b.end_row, b.end_col)
  end)

  local merged = {}
  for _, range in ipairs(ranges) do
    local prev = merged[#merged]
    if prev ~= nil and range_touches(prev, range) then
      merged[#merged] = range_union(prev, range)
    else
      merged[#merged + 1] = vim.deepcopy(range)
    end
  end
  return merged
end

local function expand_damage_through_touching_tracks(state, damage_ranges)
  local affected = vim.deepcopy(damage_ranges or {})
  local included = {}

  for _, track in ipairs(dirty_tracks(state)) do
    if track.state ~= "retired" then
      included[track.id] = true
      affected[#affected + 1] = track_range(track)
    end
  end

  affected = merge_touching_ranges(affected)
  local changed = true
  while changed do
    changed = false
    for _, track in ipairs(live_tracks(state)) do
      if not included[track.id] then
        local current = track_range(track)
        local touches = track.invalid == true
        if not touches then
          for _, damage in ipairs(affected) do
            if range_touches(current, damage) then
              touches = true
              break
            end
          end
        end

        if touches then
          included[track.id] = true
          mark_track_dirty_once(track)
          affected[#affected + 1] = current
          affected = merge_touching_ranges(affected)
          changed = true
        end
      end
    end
  end

  return affected
end

local function edit_touches_context_unit(unit, damage)
  if damage.row == damage.end_row and damage.col == damage.end_col then
    return le(unit.row, unit.col, damage.row, damage.col) and le(damage.row, damage.col, unit.end_row, unit.end_col)
  end
  return range_intersects(unit, damage)
end

local function context_units_touch_damages(context_units, damages)
  for _, unit in ipairs(context_units or {}) do
    for _, damage in ipairs(damages or {}) do
      if edit_touches_context_unit(unit, damage) then
        return true
      end
    end
  end
  return false
end

local function same_context_unit(a, b)
  return a ~= nil
    and b ~= nil
    and a.kind == b.kind
    and a.signature == b.signature
    and a.row == b.row
    and a.col == b.col
    and a.end_row == b.end_row
    and a.end_col == b.end_col
end

local function known_context_unit(context_units, candidate)
  for _, unit in ipairs(context_units or {}) do
    if same_context_unit(unit, candidate) then
      return true
    end
  end
  return false
end

local function new_context_units_touch_damages(current_context_units, scanned_context_units, damages)
  for _, unit in ipairs(scanned_context_units or {}) do
    if not known_context_unit(current_context_units, unit) then
      for _, damage in ipairs(damages or {}) do
        if edit_touches_context_unit(unit, damage) then
          return true
        end
      end
    end
  end
  return false
end

local function expand_to_stable_neighbors(bufnr, state, damage)
  local start_row, start_col = 0, 0
  local end_row, end_col = buf_end(bufnr)

  for _, track in ipairs(live_tracks(state)) do
    if track.state == "valid" and le(track.end_row, track.end_col, damage.row, damage.col) then
      start_row, start_col = track.end_row, track.end_col
    elseif track.state == "valid" and le(damage.end_row, damage.end_col, track.row, track.col) then
      end_row, end_col = track.row, track.col
      break
    end
  end

  return { row = start_row, col = start_col, end_row = end_row, end_col = end_col }
end

local function merge_windows(windows)
  table.sort(windows, function(a, b)
    return lt(a.row, a.col, b.row, b.col)
  end)

  local merged = {}
  for _, window in ipairs(windows) do
    local prev = merged[#merged]
    if prev ~= nil and le(window.row, window.col, prev.end_row, prev.end_col) then
      if lt(prev.end_row, prev.end_col, window.end_row, window.end_col) then
        prev.end_row, prev.end_col = window.end_row, window.end_col
      end
    else
      merged[#merged + 1] = vim.deepcopy(window)
    end
  end
  return merged
end

local function repair_windows(bufnr, state, damage_ranges)
  local damages = vim.deepcopy(damage_ranges or {})

  local windows = {}
  for _, damage in ipairs(damages) do
    windows[#windows + 1] = expand_to_stable_neighbors(bufnr, state, damage)
  end
  return merge_windows(windows)
end

local function tracks_in_window(state, window)
  local tracks = {}
  for _, track in ipairs(dirty_tracks(state)) do
    if track.invalid or range_intersects(track, window) then
      tracks[#tracks + 1] = track
    end
  end
  return tracks
end

local function inherit_track(bufnr, track, node, opts)
  opts = opts or {}
  track.state = "valid"
  track.invalid = false
  track.row = node.row
  track.col = node.col
  track.end_row = node.end_row
  track.end_col = node.end_col
  track.source = node.source
  track.source_hash = node.source_hash
  track.source_rows = node.source_rows
  track.source_display_kind = node.source_display_kind
  track.source_facts = vim.deepcopy(node.source_facts or {})
  track.render_whole_line = node.render_whole_line == true
  if opts.preserve_prelude ~= true then
    track.prelude_count = node.prelude_count or 0
    track.prelude_signature = node.prelude_signature
  end
  track.node_type = node.node_type
  set_core_extmark(bufnr, track)
end

local function best_pair(bufnr, tracks, nodes)
  local best = nil
  for ti, track in ipairs(tracks) do
    for ni, node in ipairs(nodes) do
      local score = overlap_bytes(bufnr, track, node)
      if best == nil or score > best.score or (score == best.score and track.id < best.track.id) then
        best = { track_index = ti, node_index = ni, track = track, node = node, score = score }
      end
    end
  end
  return best
end

local function remove_at(list, index)
  local value = list[index]
  table.remove(list, index)
  return value
end

local function scan_nodes(bufnr, state, window)
  local ok, result = pcall(state.scanner.scan, bufnr, window, state.context_units)
  if not ok then
    notify_once(tostring(result), vim.log.levels.WARN)
    return nil
  end
  if type(result) == "table" and result.nodes ~= nil then
    return result.nodes, result
  end
  return result, { nodes = result }
end

local function scan_context(bufnr, state)
  if type(state.scanner.scan_context) ~= "function" then
    notify_once("scanner does not support context repair", vim.log.levels.ERROR)
    return nil
  end

  local ok, result = pcall(state.scanner.scan_context, bufnr)
  if not ok then
    notify_once(tostring(result), vim.log.levels.WARN)
    return nil
  end
  return result
end

local function scan_all(bufnr, state)
  if type(state.scanner.scan_all) == "function" then
    local ok, result = pcall(state.scanner.scan_all, bufnr)
    if ok then
      return result
    end
    notify_once(tostring(result), vim.log.levels.WARN)
    return nil
  end

  local end_row, end_col = buf_end(bufnr)
  local nodes, result = scan_nodes(bufnr, state, { row = 0, col = 0, end_row = end_row, end_col = end_col })
  if nodes == nil then
    return nil
  end
  return result or { nodes = nodes }
end

local function reconcile_window(bufnr, state, window)
  local tracks = tracks_in_window(state, window)
  local nodes, result = scan_nodes(bufnr, state, window)
  if nodes == nil then
    return false
  end

  while #tracks > 0 and #nodes > 0 do
    local pair = best_pair(bufnr, tracks, nodes)
    local track = remove_at(tracks, pair.track_index)
    local node = remove_at(nodes, pair.node_index)
    inherit_track(bufnr, track, node, { preserve_prelude = true })
  end

  for _, track in ipairs(tracks) do
    retire(bufnr, track)
  end

  for _, node in ipairs(nodes) do
    local track = new_track(state, node)
    state.tracks[track.id] = track
    set_core_extmark(bufnr, track)
  end

  return true, result
end

local function schedule_repair(bufnr, state)
  if state.repair_scheduled then
    return
  end

  state.repair_scheduled = true

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    if state_by_buf[bufnr] ~= state then
      return
    end

    state.repair_scheduled = false
    M.repair(bufnr)
  end)
end

local function clear_namespaces(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, context_ns, 0, -1)
  clear_damage(bufnr)
  debug_projection.clear(bufnr)
end

local function seed(bufnr, state)
  local scan = scan_all(bufnr, state)
  if scan == nil then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  clear_damage(bufnr)
  debug_projection.clear(bufnr)

  for _, node in ipairs(scan.nodes or {}) do
    local track = new_track(state, node)
    state.tracks[track.id] = track
    set_core_extmark(bufnr, track)
  end

  state.context_units = scan.context_units or {}
  state.context_signature = scan.context_signature or ""
  refresh_context_extmarks(bufnr, state)

  return true
end

local function detach_state_without_api(bufnr, state)
  state.detached = true
  if state_by_buf[bufnr] == state then
    state_by_buf[bufnr] = nil
  end
end

---@param bufnr integer?
---@return boolean
function M.is_attached(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return state_by_buf[bufnr] ~= nil
end

---@param bufnr integer?
function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil then
    clear_namespaces(bufnr)
    return
  end

  detach_state_without_api(bufnr, state)
  clear_namespaces(bufnr)
end

---@param bufnr integer?
---@param opts {kind: string?, scanner: table?, debug: boolean?}?
---@return boolean
function M.attach(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}

  if not valid_loaded_buffer(bufnr) then
    return false
  end

  local kind = opts.kind or vim.bo[bufnr].filetype
  local scanner, scanner_err = resolve_scanner(kind, opts.scanner)
  if scanner == nil then
    notify_once(scanner_err or ("unsupported tracker kind: " .. tostring(kind)), vim.log.levels.WARN)
    return false
  end

  local current = state_by_buf[bufnr]
  if current ~= nil then
    if current.kind == kind then
      current.scanner = scanner
      current.debug_enabled = opts.debug == true
      current.on_repair = opts.on_repair
      refresh_debug(current)
      return true
    end

    M.detach(bufnr)
  end

  local generation = (generation_by_buf[bufnr] or 0) + 1
  generation_by_buf[bufnr] = generation

  local state = {
    bufnr = bufnr,
    kind = kind,
    scanner = scanner,
    generation = generation,
    next_track_id = 1,
    tracks = {},
    repair_scheduled = false,
    debug_enabled = opts.debug == true,
    on_repair = opts.on_repair,
    repair_tick = 0,
    context_units = {},
    context_signature = "",
    detached = false,
  }

  state_by_buf[bufnr] = state

  if not seed(bufnr, state) then
    detach_state_without_api(bufnr, state)
    clear_namespaces(bufnr)
    return false
  end

  local attached = vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, changed_buf, _, firstline, _, new_lastline)
      if state_by_buf[changed_buf] ~= state then
        return true
      end

      materialize_damage(changed_buf, line_damage_from_on_lines(changed_buf, firstline, new_lastline))
      schedule_repair(changed_buf, state)
    end,
    on_reload = function(_, reloaded_buf)
      if state_by_buf[reloaded_buf] == state then
        detach_state_without_api(reloaded_buf, state)
        vim.schedule(function()
          if state_by_buf[reloaded_buf] == nil then
            clear_namespaces(reloaded_buf)
          end
        end)
      end
      return true
    end,
    on_detach = function(_, detached_buf)
      if state_by_buf[detached_buf] == state then
        detach_state_without_api(detached_buf, state)
        clear_namespaces(detached_buf)
      end
    end,
  })

  if not attached then
    detach_state_without_api(bufnr, state)
    clear_namespaces(bufnr)
    return false
  end

  local snapshots = track_snapshots(state)
  emit_repair(
    state,
    diff_event(state, {}, snapshots, {}, state.context_units, {
      initial = true,
    })
  )
  return true
end

---@param bufnr integer?
function M.sync(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil or not valid_loaded_buffer(bufnr) then
    return
  end

  sync_tracks(bufnr, state)
  refresh_debug(state)
end

---@param bufnr integer?
---@return boolean
function M.repair(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil or not valid_loaded_buffer(bufnr) then
    return false
  end

  -- Repair consumes only current repair geometry: core track extmarks plus damage extmarks.
  sync_tracks(bufnr, state)
  local damage_ranges = expand_damage_through_touching_tracks(state, current_damage_ranges(bufnr))
  if not has_repair_geometry(damage_ranges, state) then
    return true
  end

  local before_snapshots = track_snapshots(state)
  local old_context_units = vim.deepcopy(state.context_units or {})
  local context_refresh_needed = sync_context_units(bufnr, state)
    or context_units_touch_damages(state.context_units, damage_ranges)

  for _, window in ipairs(repair_windows(bufnr, state, damage_ranges)) do
    local ok, result = reconcile_window(bufnr, state, window)
    if not ok then
      refresh_debug(state)
      return false
    end
    if new_context_units_touch_damages(state.context_units, result and result.context_units, damage_ranges) then
      context_refresh_needed = true
    end
  end

  if context_refresh_needed then
    local context_scan = scan_context(bufnr, state)
    if context_scan == nil then
      refresh_debug(state)
      return false
    end
    state.context_units = context_scan.units or context_scan.context_units or {}
    state.context_signature = context_scan.signature or context_scan.context_signature or ""
    refresh_context_extmarks(bufnr, state)
    apply_context_to_tracks(state)
  end

  clear_damage(bufnr)
  sync_tracks(bufnr, state)
  emit_repair(
    state,
    diff_event(state, before_snapshots, track_snapshots(state), old_context_units, state.context_units)
  )
  return true
end

---@param bufnr integer?
---@return table[]
function M.get_tracks(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil or not valid_loaded_buffer(bufnr) then
    return {}
  end

  sync_tracks(bufnr, state)
  return track_snapshots(state)
end

---@param bufnr integer?
---@param track_id integer
---@return table?
function M.get_track(bufnr, track_id)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil or not valid_loaded_buffer(bufnr) then
    return nil
  end

  sync_tracks(bufnr, state)
  local track = state.tracks[track_id]
  if track == nil or track.state == "retired" then
    return nil
  end
  return track_snapshot(state, track)
end

---@param bufnr integer?
---@return table
function M.get_context(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = state_by_buf[bufnr]
  if state == nil then
    return {
      changed = false,
      signature = "",
      units = {},
      changed_unit_indexes = {},
    }
  end
  return {
    changed = false,
    signature = state.context_signature or "",
    units = vim.deepcopy(state.context_units or {}),
    changed_unit_indexes = {},
  }
end

---@param ref table
---@return string
function M.track_ref_key(ref)
  return table.concat({ ref.bufnr, ref.tracker_generation or ref.generation, ref.track_id or ref.id }, ":")
end

---@return integer
function M.namespace()
  return ns
end

function M.line_count(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return 0
  end
  return vim.api.nvim_buf_line_count(bufnr)
end

function M.source_line(bufnr, row)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return ""
  end
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
end

function M.source_lines(bufnr, start_row, end_row)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
end

---@param ref table
---@return table?
function M.get_anchor(ref)
  local bufnr = normalize_bufnr(ref.bufnr)
  local track_id = ref.track_id or ref.id
  if track_id == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, track_id, { details = true })
  local row, col, details = pos[1], pos[2], pos[3]
  if row == nil then
    return nil
  end
  return {
    bufnr = bufnr,
    ns = ns,
    id = track_id,
    row = row,
    col = col,
    end_row = details.end_row or row,
    end_col = details.end_col or col,
    invalid = details.invalid == true,
  }
end

---@param ref table
---@return table?
function M.resolve_ref(ref)
  return M.get_track(ref.bufnr, ref.track_id or ref.id)
end

function M.view(ref, opts)
  opts = opts or {}
  local track = M.resolve_ref(ref)
  if track == nil then
    return nil
  end
  if opts.require_valid == true and (track.invalid == true or track.state ~= "valid") then
    return nil
  end
  return track
end

return M
