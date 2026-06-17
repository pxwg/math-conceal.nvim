local debug_projection = require("math-conceal.image.tracker.debug")

local M = {}

local ns = vim.api.nvim_create_namespace("math-conceal.image.tracker")

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

local function edit_end(start_row, start_col, row_delta, end_col)
  if row_delta == 0 then
    return start_row, start_col + end_col
  end
  return start_row + row_delta, end_col
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function point_in_range(row, col, range)
  return lt(range.row, range.col, row, col) and lt(row, col, range.end_row, range.end_col)
end

local function edit_touches_track(track, row, col, end_row, end_col)
  if row == end_row and col == end_col then
    return point_in_range(row, col, track)
  end
  return range_intersects(track, { row = row, col = col, end_row = end_row, end_col = end_col })
end

local function resolve_scanner(kind, scanner)
  if scanner ~= nil then
    return scanner
  end

  if kind == "typst" then
    return require("math-conceal.image.tracker.typst")
  end

  return nil, "unsupported tracker kind: " .. tostring(kind)
end

local function notify_once(message, level)
  vim.notify_once("math-conceal image tracker: " .. message, level or vim.log.levels.WARN)
end

local function buf_end(bufnr)
  local last = vim.api.nvim_buf_line_count(bufnr) - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, last, last + 1, false)[1] or ""
  return last, #line
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
    node_type = node.node_type,
  }
end

local function retire(bufnr, track)
  track.state = "retired"
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, track.id)
end

local function sync_track(bufnr, track)
  if track.state == "retired" then
    return
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, track.id, { details = true })
  local row, col, details = pos[1], pos[2], pos[3]
  if row == nil then
    track.state = "dirty"
    track.invalid = true
    return
  end

  track.row = row
  track.col = col
  track.end_row = details.end_row or row
  track.end_col = details.end_col or col
  track.invalid = details.invalid == true
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

local function has_pending_repair(state)
  return #state.damage_ranges > 0 or has_dirty_track(state)
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

local function repair_windows(bufnr, state)
  local damages = vim.deepcopy(state.damage_ranges)

  for _, track in ipairs(dirty_tracks(state)) do
    damages[#damages + 1] = { row = track.row, col = track.col, end_row = track.end_row, end_col = track.end_col }
  end

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

local function inherit_track(bufnr, track, node)
  track.state = "valid"
  track.invalid = false
  track.row = node.row
  track.col = node.col
  track.end_row = node.end_row
  track.end_col = node.end_col
  track.source = node.source
  track.source_hash = node.source_hash
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
  local ok, nodes = pcall(state.scanner.scan, bufnr, window)
  if not ok then
    notify_once(tostring(nodes), vim.log.levels.WARN)
    return nil
  end
  return nodes
end

local function reconcile_window(bufnr, state, window)
  local tracks = tracks_in_window(state, window)
  local nodes = scan_nodes(bufnr, state, window)
  if nodes == nil then
    return false
  end

  while #tracks > 0 and #nodes > 0 do
    local pair = best_pair(bufnr, tracks, nodes)
    local track = remove_at(tracks, pair.track_index)
    local node = remove_at(nodes, pair.node_index)
    inherit_track(bufnr, track, node)
  end

  for _, track in ipairs(tracks) do
    retire(bufnr, track)
  end

  for _, node in ipairs(nodes) do
    local track = new_track(state, node)
    state.tracks[track.id] = track
    set_core_extmark(bufnr, track)
  end

  return true
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
  debug_projection.clear(bufnr)
end

local function seed(bufnr, state)
  local end_row, end_col = buf_end(bufnr)
  local nodes = scan_nodes(bufnr, state, { row = 0, col = 0, end_row = end_row, end_col = end_col })
  if nodes == nil then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  debug_projection.clear(bufnr)

  for _, node in ipairs(nodes) do
    local track = new_track(state, node)
    state.tracks[track.id] = track
    set_core_extmark(bufnr, track)
  end

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
    damage_ranges = {},
    repair_scheduled = false,
    debug_enabled = opts.debug == true,
    detached = false,
  }

  state_by_buf[bufnr] = state

  if not seed(bufnr, state) then
    detach_state_without_api(bufnr, state)
    clear_namespaces(bufnr)
    return false
  end

  local attached = vim.api.nvim_buf_attach(bufnr, false, {
    on_bytes = function(_, changed_buf, _, row, col, _, old_end_row, old_end_col, _, new_end_row, new_end_col)
      if state_by_buf[changed_buf] ~= state then
        return true
      end

      local old_row, old_col = edit_end(row, col, old_end_row, old_end_col)
      local new_row, new_col = edit_end(row, col, new_end_row, new_end_col)

      for _, track in pairs(state.tracks) do
        if track.state ~= "retired" and edit_touches_track(track, row, col, old_row, old_col) then
          track.state = "dirty"
          track.rev = track.rev + 1
        end
      end

      state.damage_ranges[#state.damage_ranges + 1] = { row = row, col = col, end_row = new_row, end_col = new_col }
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

  refresh_debug(state)
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

  sync_tracks(bufnr, state)
  if not has_pending_repair(state) then
    refresh_debug(state)
    return true
  end

  for _, window in ipairs(repair_windows(bufnr, state)) do
    if not reconcile_window(bufnr, state, window) then
      refresh_debug(state)
      return false
    end
  end

  state.damage_ranges = {}
  sync_tracks(bufnr, state)
  refresh_debug(state)
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

---@param ref table
---@return string
function M.track_ref_key(ref)
  return table.concat({ ref.bufnr, ref.tracker_generation or ref.generation, ref.track_id or ref.id }, ":")
end

return M
