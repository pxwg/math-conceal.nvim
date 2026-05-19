--- Pure reducer for the full-overlay state machine.

local types = require("math-conceal.image.machine.types")

local M = {}

local function deepcopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[deepcopy(k, seen)] = deepcopy(v, seen)
  end
  return out
end

--- Return the state for in-place mutation.
--- The caller (runtime.dispatch) immediately replaces state.machine_state with
--- the return value, so the previous reference is never read again.  A full
--- deepcopy here was the primary source of progressive slowdown: O(state_size)
--- per dispatch × ~6 dispatches per render cycle × every keystroke.
local function clone_state(state)
  return state or types.initial_state()
end

local function copy_range(range)
  if range == nil then
    return nil
  end
  return { range[1], range[2], range[3], range[4] }
end

local function source_rows_from_range(range)
  if range == nil then
    return 1
  end
  return math.max(1, (range[3] or range[1] or 0) - (range[1] or 0) + 1)
end

local function ranges_equal(a, b)
  if a == nil or b == nil then
    return a == b
  end
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local function pos_lt(row_a, col_a, row_b, col_b)
  return row_a < row_b or (row_a == row_b and col_a < col_b)
end

local function ranges_overlap(a, b)
  if a == nil or b == nil then
    return false
  end
  return pos_lt(a[1], a[2], b[3], b[4]) and pos_lt(b[1], b[2], a[3], a[4])
end

local function range_list_overlaps(range, ranges)
  for _, dirty in ipairs(ranges or {}) do
    if ranges_overlap(range, dirty) then
      return true
    end
  end
  return false
end

local function record_overlay_binding(overlay, buffer_version, layout_version, display_range)
  if overlay == nil then
    return
  end
  overlay.binding_buffer_version = buffer_version
  overlay.binding_layout_version = layout_version
  overlay.binding_display_range = copy_range(display_range)
end

local function row_overlap_len(a, b)
  local top = math.max(a[1], b[1])
  local bottom = math.min(a[3], b[3])
  if bottom < top then
    return 0
  end
  return bottom - top + 1
end

local function row_gap_len(a, b)
  if a[3] < b[1] then
    return b[1] - a[3]
  end
  if b[3] < a[1] then
    return a[1] - b[3]
  end
  return 0
end

local function row_ranges_overlap(a, b)
  return row_overlap_len(a, b) > 0
end

local function col_delta_len(a, b)
  return math.abs(a[2] - b[2]) + math.abs(a[4] - b[4])
end

local function semantics_key(semantics)
  semantics = semantics or {}
  return table.concat({
    tostring(semantics.constraint_kind or ""),
    tostring(semantics.display_kind or ""),
    tostring(semantics.source_kind or ""),
    tostring(semantics.backend_id or ""),
    tostring(semantics.backend_node_type or ""),
    tostring(semantics.markdown_math == true),
    tostring(semantics.render_whole_line == true),
  }, "\0")
end

local function strong_identity_key(value)
  if value == nil then
    return nil
  end
  return table.concat({
    tostring(value.node_type or ""),
    tostring(value.source_text_hash or ""),
    tostring(value.context_hash or ""),
    tostring(value.prelude_count or 0),
    semantics_key(value.semantics),
  }, "\0")
end

local function semantics_equal(a, b)
  return semantics_key(a) == semantics_key(b)
end

local function next_id(counters, field, prefix)
  local n = counters[field] or 1
  counters[field] = n + 1
  return prefix .. tostring(n)
end

local function ensure_slot_registry(buf)
  buf.slots = buf.slots or {}
  buf.slot_order = buf.slot_order or {}
  buf.next_slot_id = buf.next_slot_id or 1
  buf.shape_epoch = buf.shape_epoch or 0
end

local function ensure_buffer(state, bufnr, project_scope_id)
  local buf = state.buffers[bufnr]
  if buf == nil then
    buf = {
      bufnr = bufnr,
      project_scope_id = project_scope_id,
      buffer_version = 0,
      layout_version = 0,
      render_epoch = 0,
      active_request_id = nil,
      nodes = {},
      node_order = {},
      slots = {},
      slot_order = {},
      next_slot_id = 1,
      shape_epoch = 0,
      render_context_hash = nil,
      context_id = nil,
      context_rev = 1,
    }
    state.buffers[bufnr] = buf
  end
  ensure_slot_registry(buf)
  buf.context_rev = buf.context_rev or 1
  return buf
end

local function next_slot_id(buf)
  ensure_slot_registry(buf)
  local n = buf.next_slot_id or 1
  buf.next_slot_id = n + 1
  return "slot:" .. tostring(n)
end

local function allocate_slot(buf, node)
  local slot_id = next_slot_id(buf)
  local slot = {
    slot_id = slot_id,
    page_index = #(buf.slot_order or {}) + 1,
    node_id = node.node_id,
    source_text = node.source_text,
    source_str = node.source_str,
    source_text_hash = node.source_text_hash,
    backend_node_type = node.backend_node_type,
    requires_mitex = node.requires_mitex,
    source_range = copy_range(node.source_range),
    source_rows = source_rows_from_range(node.source_range),
    context_id = buf.context_id,
    context_rev = buf.context_rev,
    context_hash = node.context_hash,
    prelude_count = node.prelude_count or 0,
    node_type = node.node_type,
    semantics = deepcopy(node.semantics),
    display_range = copy_range(node.display_range),
    visible_overlay_id = node.visible_overlay_id,
    candidate_overlay_id = node.candidate_overlay_id,
    status = "dirty",
    dirty = true,
    pending_request_id = nil,
  }
  buf.slots[slot_id] = slot
  buf.slot_order[#buf.slot_order + 1] = slot_id
  buf.shape_epoch = (buf.shape_epoch or 0) + 1
  node.slot_id = slot_id
  return slot
end

local function slot_inputs_equal(slot, node)
  if slot == nil or node == nil then
    return false
  end
  return slot.source_text_hash == node.source_text_hash
    and slot.context_hash == node.context_hash
    and (slot.prelude_count or 0) == (node.prelude_count or 0)
    and slot.node_type == node.node_type
    and source_rows_from_range(slot.source_range) == source_rows_from_range(node.source_range)
    and semantics_equal(slot.semantics, node.semantics)
end

local function sync_slot_from_node(buf, node, force_dirty)
  ensure_slot_registry(buf)
  local slot = node.slot_id and buf.slots[node.slot_id] or nil
  if slot == nil then
    return allocate_slot(buf, node)
  end

  local changed = not slot_inputs_equal(slot, node)
  slot.node_id = node.node_id
  slot.source_text = node.source_text
  slot.source_str = node.source_str
  slot.source_text_hash = node.source_text_hash
  slot.backend_node_type = node.backend_node_type
  slot.requires_mitex = node.requires_mitex
  slot.source_range = copy_range(node.source_range)
  slot.source_rows = source_rows_from_range(node.source_range)
  slot.context_id = buf.context_id
  slot.context_rev = buf.context_rev
  slot.context_hash = node.context_hash
  slot.prelude_count = node.prelude_count or 0
  slot.node_type = node.node_type
  slot.semantics = deepcopy(node.semantics)
  slot.display_range = copy_range(node.display_range)
  slot.visible_overlay_id = node.visible_overlay_id
  slot.candidate_overlay_id = node.candidate_overlay_id

  if force_dirty or changed or node.status == "pending" or node.status == "stale" then
    slot.status = "dirty"
    slot.dirty = true
  elseif node.candidate_overlay_id ~= nil then
    slot.status = "dirty"
    slot.dirty = true
  elseif node.visible_overlay_id ~= nil then
    slot.status = "clean"
    slot.dirty = false
    slot.pending_request_id = nil
  else
    slot.status = "dirty"
    slot.dirty = true
  end

  return slot
end

local function tombstone_slot(buf, slot_id, request_dirty)
  ensure_slot_registry(buf)
  local slot = slot_id and buf.slots[slot_id] or nil
  if slot == nil then
    return
  end
  slot.node_id = nil
  slot.source_text = "[]"
  slot.source_text_hash = nil
  slot.source_range = slot.source_range and copy_range(slot.source_range) or { 0, 0, 0, 0 }
  slot.source_rows = 1
  slot.context_hash = nil
  slot.prelude_count = 0
  slot.node_type = nil
  slot.backend_node_type = nil
  slot.semantics = nil
  slot.display_range = nil
  slot.visible_overlay_id = nil
  slot.candidate_overlay_id = nil
  if slot.status ~= "tombstone" then
    slot.status = "tombstone"
    slot.dirty = true
    slot.pending_request_id = nil
  elseif request_dirty then
    slot.dirty = true
  end
end

local function node_matches_scan(node, scanned, project_scope_id, bufnr)
  if node == nil or scanned == nil then
    return false
  end
  if node.status == "deleted_confirmed" then
    return false
  end
  if node.bufnr ~= bufnr or node.project_scope_id ~= project_scope_id then
    return false
  end
  if node.node_type ~= scanned.node_type then
    return false
  end
  return strong_identity_key(node) == strong_identity_key(scanned)
end

local function node_identity_can_range_match(node, scanned, project_scope_id, bufnr)
  if node == nil or scanned == nil then
    return false
  end
  if node.status == "deleted_confirmed" or node.status == "orphaned" then
    return false
  end
  if node.bufnr ~= bufnr or node.project_scope_id ~= project_scope_id then
    return false
  end
  if node.node_type ~= scanned.node_type then
    return false
  end
  if node.context_hash ~= scanned.context_hash then
    return false
  end
  if (node.prelude_count or 0) ~= (scanned.prelude_count or 0) then
    return false
  end
  if not semantics_equal(node.semantics, scanned.semantics) then
    return false
  end

  local ordinal_delta = math.abs((node.item_idx or 0) - (scanned.item_idx or 0))
  if ordinal_delta > 1 then
    return false
  end

  local overlap = row_overlap_len(node.source_range, scanned.source_range)
  local gap = row_gap_len(node.source_range, scanned.source_range)
  local display_overlap = row_ranges_overlap(node.display_range, scanned.display_range)
  return overlap > 0 or display_overlap or (gap <= 1 and ordinal_delta <= 1)
end

local function node_identity_rank(node)
  if node.status == "orphaned" then
    return 1
  end
  return 2
end

local function best_by_range(old_nodes, scanned, used_old, project_scope_id, bufnr, predicate)
  local best = nil
  local best_rank = -1
  local best_overlap = -1
  local best_gap = math.huge
  local best_col_delta = math.huge

  for _, old in pairs(old_nodes or {}) do
    if not used_old[old.node_id] and predicate(old, scanned, project_scope_id, bufnr) then
      local rank = node_identity_rank(old)
      local overlap = row_overlap_len(old.source_range, scanned.source_range)
      local gap = row_gap_len(old.source_range, scanned.source_range)
      local col_delta = col_delta_len(old.source_range, scanned.source_range)
      local ordinal_delta = math.abs((old.item_idx or 0) - (scanned.item_idx or 0))
      if
        rank > best_rank
        or (rank == best_rank and overlap > best_overlap)
        or (rank == best_rank and overlap == best_overlap and gap < best_gap)
        or (rank == best_rank and overlap == best_overlap and gap == best_gap and ordinal_delta < math.abs(
          (best and best.item_idx or 0) - (scanned.item_idx or 0)
        ))
        or (rank == best_rank and overlap == best_overlap and gap == best_gap and col_delta < best_col_delta)
      then
        best = old
        best_rank = rank
        best_overlap = overlap
        best_gap = gap
        best_col_delta = col_delta
      end
    end
  end

  return best
end

local function best_exact_identity_match(old_nodes, scanned, used_old, project_scope_id, bufnr, predicate)
  local best = nil
  local best_rank = -1
  local best_ordinal_delta = math.huge
  local best_overlap = -1
  local best_gap = math.huge
  local best_col_delta = math.huge

  for _, old in pairs(old_nodes or {}) do
    if not used_old[old.node_id] and predicate(old, scanned, project_scope_id, bufnr) then
      local rank = node_identity_rank(old)
      local ordinal_delta = math.abs((old.item_idx or 0) - (scanned.item_idx or 0))
      local overlap = row_overlap_len(old.source_range, scanned.source_range)
      local gap = row_gap_len(old.source_range, scanned.source_range)
      local col_delta = col_delta_len(old.source_range, scanned.source_range)
      if
        rank > best_rank
        or (rank == best_rank and ordinal_delta < best_ordinal_delta)
        or (rank == best_rank and ordinal_delta == best_ordinal_delta and overlap > best_overlap)
        or (rank == best_rank and ordinal_delta == best_ordinal_delta and overlap == best_overlap and gap < best_gap)
        or (
          rank == best_rank
          and ordinal_delta == best_ordinal_delta
          and overlap == best_overlap
          and gap == best_gap
          and col_delta < best_col_delta
        )
      then
        best = old
        best_rank = rank
        best_ordinal_delta = ordinal_delta
        best_overlap = overlap
        best_gap = gap
        best_col_delta = col_delta
      end
    end
  end

  return best
end

local retire_orphan_node

local function retire_orphans_without_replacement(state, buf, effects)
  for _, orphan_id in ipairs(buf.node_order or {}) do
    local orphan = buf.nodes[orphan_id]
    if orphan ~= nil and orphan.status == "orphaned" and orphan.visible_overlay_id ~= nil then
      local has_pending_replacement = false
      for _, node_id in ipairs(buf.node_order or {}) do
        local node = buf.nodes[node_id]
        if
          node_id ~= orphan_id
          and node ~= nil
          and node.status ~= "orphaned"
          and node.status ~= "deleted_confirmed"
          and row_ranges_overlap(orphan.display_range, node.display_range)
        then
          if node.visible_overlay_id == nil or node.candidate_overlay_id ~= nil or node.status ~= "stable" then
            has_pending_replacement = true
            break
          end
          retire_orphan_node(state, orphan, effects)
          break
        end
      end
      if not has_pending_replacement and orphan.status == "orphaned" then
        retire_orphan_node(state, orphan, effects)
      end
    elseif orphan ~= nil and orphan.status == "orphaned" then
      orphan.status = "deleted_confirmed"
      orphan.candidate_overlay_id = nil
      orphan.visible_overlay_id = nil
    end
  end
end

local function find_stable_key_node(old_nodes, scanned, used_old, project_scope_id, bufnr)
  if scanned.stable_key == nil then
    return nil
  end
  for _, old in pairs(old_nodes or {}) do
    if
      not used_old[old.node_id]
      and old.status ~= "deleted_confirmed"
      and old.stable_key == scanned.stable_key
      and old.bufnr == bufnr
      and old.project_scope_id == project_scope_id
    then
      return old
    end
  end
end

local function find_best_old_node(old_nodes, scanned, used_old, project_scope_id, bufnr, reserved_strong_keys)
  local stable = find_stable_key_node(old_nodes, scanned, used_old, project_scope_id, bufnr)
  if stable ~= nil then
    return stable
  end

  local exact = best_exact_identity_match(old_nodes, scanned, used_old, project_scope_id, bufnr, node_matches_scan)
  if exact ~= nil then
    return exact
  end

  return best_by_range(old_nodes, scanned, used_old, project_scope_id, bufnr, function(old, scan, scope_id, buffer)
    local key = strong_identity_key(old)
    if key ~= nil and reserved_strong_keys ~= nil and (reserved_strong_keys[key] or 0) > 0 then
      return false
    end
    return node_identity_can_range_match(old, scan, scope_id, buffer)
  end)
end

retire_orphan_node = function(state, orphan, effects)
  local overlay = state.overlays[orphan.visible_overlay_id]
  if overlay ~= nil then
    overlay.status = "retiring"
    effects[#effects + 1] = {
      kind = "retire_overlay",
      overlay_id = overlay.overlay_id,
    }
  end
  orphan.visible_overlay_id = nil
  orphan.candidate_overlay_id = nil
  orphan.status = "deleted_confirmed"
end

local function retire_overlapping_orphans(state, buf, committed_node, effects)
  for _, other_id in ipairs(buf.node_order or {}) do
    if other_id ~= committed_node.node_id then
      local other = buf.nodes[other_id]
      if
        other ~= nil
        and other.status == "orphaned"
        and other.visible_overlay_id ~= nil
        and row_ranges_overlap(other.display_range, committed_node.display_range)
      then
        retire_orphan_node(state, other, effects)
      end
    end
  end
end

local function retire_orphans_covered_by_visible_nodes(state, buf, effects)
  for _, orphan_id in ipairs(buf.node_order or {}) do
    local orphan = buf.nodes[orphan_id]
    if orphan ~= nil and orphan.status == "orphaned" and orphan.visible_overlay_id ~= nil then
      for _, node_id in ipairs(buf.node_order or {}) do
        local node = buf.nodes[node_id]
        if
          node_id ~= orphan_id
          and node ~= nil
          and node.status ~= "orphaned"
          and node.status ~= "deleted_confirmed"
          and node.visible_overlay_id ~= nil
          and row_ranges_overlap(orphan.display_range, node.display_range)
        then
          retire_orphan_node(state, orphan, effects)
          break
        end
      end
    end
  end
end

local function node_is_layout_sensitive(node)
  local semantics = (node and node.semantics) or {}
  return semantics.constraint_kind == "flow"
end

local function node_render_inputs_equal(node, scanned, layout_version)
  local layout_equal = (not node_is_layout_sensitive(scanned))
    or tonumber(node.last_layout_version) == tonumber(layout_version)
  return node.source_text_hash == scanned.source_text_hash
    and node.context_hash == scanned.context_hash
    and node.prelude_count == (scanned.prelude_count or 0)
    and node.node_type == scanned.node_type
    and source_rows_from_range(node.source_range) == source_rows_from_range(scanned.source_range)
    and semantics_equal(node.semantics, scanned.semantics)
    and layout_equal
end

local function patch_node(prev, scanned, buffer_version, layout_version)
  local node = prev
  node.stable_key = scanned.stable_key
  node.item_idx = scanned.item_idx
  node.node_type = scanned.node_type
  node.source_range = copy_range(scanned.source_range)
  node.display_range = copy_range(scanned.display_range)
  node.display_prefix = scanned.display_prefix
  node.display_suffix = scanned.display_suffix
  node.source_text = scanned.source_text
  node.source_str = scanned.source_str
  node.source_text_hash = scanned.source_text_hash
  node.backend_node_type = scanned.backend_node_type
  node.requires_mitex = scanned.requires_mitex
  node.render_in_coverage = scanned.render_in_coverage ~= false
  node.render_priority = scanned.render_priority
  node.context_hash = scanned.context_hash
  node.prelude_count = scanned.prelude_count or 0
  node.semantics = deepcopy(scanned.semantics)
  node.last_buffer_version = buffer_version
  node.last_layout_version = layout_version
  return node
end

local function new_node(state, bufnr, project_scope_id, scanned, buffer_version, layout_version)
  return {
    node_id = next_id(state.counters, "next_node_id", "node:"),
    slot_id = nil,
    stable_key = scanned.stable_key,
    bufnr = bufnr,
    project_scope_id = project_scope_id,
    item_idx = scanned.item_idx,
    node_type = scanned.node_type,
    backend_node_type = scanned.backend_node_type,
    source_range = copy_range(scanned.source_range),
    display_range = copy_range(scanned.display_range),
    display_prefix = scanned.display_prefix,
    display_suffix = scanned.display_suffix,
    source_text = scanned.source_text,
    source_str = scanned.source_str,
    source_text_hash = scanned.source_text_hash,
    node_rev = 1,
    requires_mitex = scanned.requires_mitex,
    render_in_coverage = scanned.render_in_coverage ~= false,
    render_priority = scanned.render_priority,
    context_hash = scanned.context_hash,
    prelude_count = scanned.prelude_count or 0,
    semantics = deepcopy(scanned.semantics),
    status = "pending",
    visible_overlay_id = nil,
    candidate_overlay_id = nil,
    last_rendered_epoch = nil,
    last_buffer_version = buffer_version,
    last_layout_version = layout_version,
  }
end

local function new_overlay(state, buf, node, request_id, page_index, slot_id)
  local has_visible = node.visible_overlay_id ~= nil
  local overlay = {
    overlay_id = next_id(state.counters, "next_overlay_id", "overlay:"),
    slot_id = slot_id or node.slot_id,
    owner_node_id = node.node_id,
    owner_bufnr = buf.bufnr,
    owner_project_scope_id = buf.project_scope_id,
    request_id = request_id,
    page_index = page_index,
    session_id = "full:" .. tostring(buf.bufnr),
    render_epoch = buf.render_epoch,
    node_rev = node.node_rev,
    context_id = buf.context_id,
    context_rev = buf.context_rev,
    source_text_hash = node.source_text_hash,
    backend_node_type = node.backend_node_type,
    buffer_version = buf.buffer_version,
    layout_version = buf.layout_version,
    extmark_id = nil,
    image_id = nil,
    page_path = nil,
    page_stamp = nil,
    natural_cols = nil,
    natural_rows = nil,
    source_rows = nil,
    terminal_upload_epoch = nil,
    binding_buffer_version = nil,
    binding_layout_version = nil,
    binding_display_range = nil,
    status = has_visible and "rendering" or "placeholder",
  }
  state.overlays[overlay.overlay_id] = overlay
  return overlay
end

local function render_job_from_node(node, overlay)
  return {
    request_id = overlay.request_id,
    request_page_index = overlay.page_index,
    overlay_id = overlay.overlay_id,
    slot_id = overlay.slot_id or node.slot_id,
    node_id = node.node_id,
    bufnr = node.bufnr,
    project_scope_id = node.project_scope_id,
    render_epoch = overlay.render_epoch,
    node_rev = overlay.node_rev,
    context_id = overlay.context_id,
    context_rev = overlay.context_rev,
    buffer_version = overlay.buffer_version,
    layout_version = overlay.layout_version,
    item_idx = node.item_idx,
    range = copy_range(node.source_range),
    display_range = copy_range(node.display_range),
    display_prefix = node.display_prefix,
    display_suffix = node.display_suffix,
    source_text = node.source_text,
    source_text_hash = node.source_text_hash,
    backend_node_type = node.backend_node_type,
    source_str = node.source_str,
    str = node.source_text,
    requires_mitex = node.requires_mitex,
    prelude_count = node.prelude_count,
    semantics = deepcopy(node.semantics),
    image_id = overlay.image_id,
    extmark_id = overlay.extmark_id,
    is_stub = false,
    is_tombstone = false,
    slot_status = "dirty",
    slot_dirty = true,
  }
end

local function should_rerender_node(node)
  return node.status == "stale" or node.status == "pending"
end

local function overlay_can_bind_without_render(overlay)
  return overlay ~= nil
    and overlay.status == "visible"
    and overlay.image_id ~= nil
    and overlay.extmark_id ~= nil
    and overlay.page_path ~= nil
    and overlay.natural_cols ~= nil
    and overlay.natural_rows ~= nil
end

local function overlay_binding_current(overlay, node, buffer_version, layout_version)
  return overlay ~= nil
    and overlay.binding_buffer_version == buffer_version
    and overlay.binding_layout_version == layout_version
    and ranges_equal(overlay.binding_display_range, node and node.display_range)
end

local function node_needs_overlay_binding_refresh(state, node, ev)
  if node == nil or node.status ~= "stable" or node.candidate_overlay_id ~= nil or node.visible_overlay_id == nil then
    return false
  end

  local overlay = state.overlays[node.visible_overlay_id]
  if not overlay_can_bind_without_render(overlay) then
    return false
  end
  if overlay.owner_node_id ~= node.node_id then
    return false
  end
  if overlay_binding_current(overlay, node, ev.buffer_version, ev.layout_version) then
    return false
  end
  if overlay.binding_display_range == nil or overlay.binding_layout_version ~= ev.layout_version then
    return true
  end
  if not ranges_equal(overlay.binding_display_range, node.display_range) then
    return true
  end
  return range_list_overlaps(node.display_range, ev.binding_dirty_ranges)
    or range_list_overlaps(overlay.binding_display_range, ev.binding_dirty_ranges)
end

local function render_stub_from_node(node, slot)
  return {
    request_page_index = slot.page_index,
    overlay_id = nil,
    slot_id = slot.slot_id,
    node_id = node.node_id,
    bufnr = node.bufnr,
    project_scope_id = node.project_scope_id,
    node_rev = node.node_rev,
    context_id = slot.context_id,
    context_rev = slot.context_rev,
    item_idx = node.item_idx,
    range = copy_range(node.source_range),
    display_range = copy_range(node.display_range),
    display_prefix = node.display_prefix,
    display_suffix = node.display_suffix,
    source_text = node.source_text,
    source_text_hash = node.source_text_hash,
    backend_node_type = node.backend_node_type,
    source_str = node.source_str,
    str = node.source_text,
    requires_mitex = node.requires_mitex,
    prelude_count = node.prelude_count,
    semantics = deepcopy(node.semantics),
    is_stub = true,
    is_tombstone = false,
    slot_status = slot.status,
    slot_dirty = slot.dirty == true,
  }
end

local function render_tombstone_stub(slot)
  return {
    request_page_index = slot.page_index,
    overlay_id = nil,
    slot_id = slot.slot_id,
    node_id = nil,
    bufnr = nil,
    project_scope_id = nil,
    item_idx = slot.page_index,
    range = copy_range(slot.source_range) or { 0, 0, 0, 0 },
    display_range = nil,
    source_text = slot.source_text or "[]",
    source_str = slot.source_str,
    str = slot.source_text or "[]",
    requires_mitex = slot.requires_mitex,
    backend_node_type = slot.backend_node_type,
    prelude_count = 0,
    semantics = nil,
    is_stub = true,
    is_tombstone = true,
    slot_status = "tombstone",
    slot_dirty = slot.dirty == true,
  }
end

local function retire_old_request_candidates(state, buf, old_request_id, effects, new_request_id)
  if old_request_id == nil then
    return
  end

  effects[#effects + 1] = {
    kind = "abandon_request",
    bufnr = buf.bufnr,
    old_request_id = old_request_id,
    new_request_id = new_request_id,
  }

  for _, overlay in pairs(state.overlays) do
    if overlay.owner_bufnr == buf.bufnr and overlay.request_id == old_request_id and overlay.status ~= "visible" then
      overlay.status = "retiring"
      effects[#effects + 1] = {
        kind = "retire_overlay",
        overlay_id = overlay.overlay_id,
      }
    end
  end
end

local function retire_node_candidate(state, node, effects)
  if node == nil or node.candidate_overlay_id == nil then
    return
  end

  local overlay = state.overlays[node.candidate_overlay_id]
  if
    overlay ~= nil
    and overlay.status ~= "visible"
    and overlay.status ~= "retiring"
    and overlay.status ~= "retired"
  then
    overlay.status = "retiring"
    effects[#effects + 1] = {
      kind = "retire_overlay",
      overlay_id = overlay.overlay_id,
    }
  end
  node.candidate_overlay_id = nil
end

local function pending_candidate_matches_node(state, buf, node)
  if node == nil or node.candidate_overlay_id == nil then
    return false
  end
  local overlay = state.overlays[node.candidate_overlay_id]
  return overlay ~= nil
    and overlay.status ~= "visible"
    and overlay.status ~= "retiring"
    and overlay.status ~= "retired"
    and overlay.owner_node_id == node.node_id
    and overlay.owner_bufnr == buf.bufnr
    and overlay.owner_project_scope_id == buf.project_scope_id
    and overlay.node_rev == node.node_rev
    and overlay.context_id == buf.context_id
    and overlay.context_rev == buf.context_rev
    and overlay.source_text_hash == node.source_text_hash
end

local function request_has_pending_overlay(state, buf, request_id)
  if request_id == nil then
    return false
  end
  for _, overlay in pairs(state.overlays or {}) do
    if
      overlay.owner_bufnr == buf.bufnr
      and overlay.request_id == request_id
      and overlay.status ~= "visible"
      and overlay.status ~= "retiring"
      and overlay.status ~= "retired"
    then
      return true
    end
  end
  return false
end

local function abandon_idle_request(state, buf, effects)
  if buf.active_request_id == nil then
    return
  end

  retire_old_request_candidates(state, buf, buf.active_request_id, effects, nil)
  buf.active_request_id = nil
end

local function mark_slot_committed(buf, node, overlay)
  if buf == nil or node == nil or overlay == nil then
    return
  end
  ensure_slot_registry(buf)
  local slot = node.slot_id and buf.slots[node.slot_id] or nil
  if slot == nil then
    return
  end
  slot.node_id = node.node_id
  slot.source_text = node.source_text
  slot.source_str = node.source_str
  slot.source_text_hash = node.source_text_hash
  slot.requires_mitex = node.requires_mitex
  slot.source_range = copy_range(node.source_range)
  slot.source_rows = source_rows_from_range(node.source_range)
  slot.context_hash = node.context_hash
  slot.prelude_count = node.prelude_count or 0
  slot.node_type = node.node_type
  slot.semantics = deepcopy(node.semantics)
  slot.display_range = copy_range(node.display_range)
  slot.visible_overlay_id = overlay.overlay_id
  slot.candidate_overlay_id = nil
  slot.pending_request_id = nil
  slot.status = "clean"
  slot.dirty = false
end

local function reduce_nodes_scanned(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local buf = ensure_buffer(new_state, ev.bufnr, ev.project_scope_id)
  local project_changed = buf.project_scope_id ~= nil and buf.project_scope_id ~= ev.project_scope_id
  local next_context_hash = ev.render_context_hash or ev.project_scope_id
  local has_existing_slots = #(buf.slot_order or {}) > 0
  local context_changed = next_context_hash ~= nil
    and buf.render_context_hash ~= next_context_hash
    and (buf.render_context_hash ~= nil or has_existing_slots)
  buf.project_scope_id = ev.project_scope_id
  buf.context_id = ev.project_scope_id or buf.context_id
  buf.context_rev = buf.context_rev or 1
  if project_changed or context_changed then
    buf.context_rev = buf.context_rev + 1
  end
  buf.render_context_hash = next_context_hash
  buf.buffer_version = ev.buffer_version
  buf.layout_version = ev.layout_version
  ensure_slot_registry(buf)
  if project_changed or context_changed then
    buf.shape_epoch = (buf.shape_epoch or 0) + 1
    for _, slot in pairs(buf.slots or {}) do
      if slot.status == "tombstone" then
        slot.dirty = true
      else
        slot.status = "dirty"
        slot.dirty = true
      end
    end
  end

  local old_nodes = buf.nodes or {}
  local next_nodes = {}
  local next_order = {}
  local used_old = {}
  local moved_visible_nodes = {}
  local reserved_strong_keys = {}
  for idx, scanned in ipairs(ev.scanned_nodes or {}) do
    scanned.item_idx = scanned.item_idx or idx
    local key = strong_identity_key(scanned)
    if key ~= nil then
      reserved_strong_keys[key] = (reserved_strong_keys[key] or 0) + 1
    end
  end

  for idx, scanned in ipairs(ev.scanned_nodes or {}) do
    scanned.item_idx = scanned.item_idx or idx
    local scan_key = strong_identity_key(scanned)
    if scan_key ~= nil and reserved_strong_keys[scan_key] ~= nil then
      reserved_strong_keys[scan_key] = math.max(0, reserved_strong_keys[scan_key] - 1)
    end
    local prev = find_best_old_node(old_nodes, scanned, used_old, ev.project_scope_id, ev.bufnr, reserved_strong_keys)
    local node

    if prev ~= nil then
      used_old[prev.node_id] = true
      local unchanged = node_render_inputs_equal(prev, scanned, ev.layout_version)
      local display_range_changed = not ranges_equal(prev.display_range, scanned.display_range)
      local prev_node_rev = prev.node_rev or 1
      node = patch_node(prev, scanned, ev.buffer_version, ev.layout_version)
      node.node_rev = unchanged and prev_node_rev or (prev_node_rev + 1)
      if unchanged and prev.status ~= "deleted_confirmed" then
        if node.candidate_overlay_id ~= nil then
          node.status = prev.status
        elseif node.visible_overlay_id ~= nil then
          node.status = "stable"
        else
          node.status = "pending"
        end
      else
        retire_node_candidate(new_state, node, effects)
        node.status = node.visible_overlay_id ~= nil and "stale" or "pending"
      end
      if
        unchanged
        and display_range_changed
        and node.status == "stable"
        and node.candidate_overlay_id == nil
        and node.visible_overlay_id ~= nil
      then
        moved_visible_nodes[node.node_id] = true
      end
    else
      node = new_node(new_state, ev.bufnr, ev.project_scope_id, scanned, ev.buffer_version, ev.layout_version)
    end

    sync_slot_from_node(buf, node, project_changed or context_changed)
    next_nodes[node.node_id] = node
    next_order[#next_order + 1] = node.node_id
  end

  for node_id, old in pairs(old_nodes) do
    if not used_old[node_id] then
      retire_node_candidate(new_state, old, effects)
      old.missing_since_buffer_version = ev.buffer_version
      tombstone_slot(buf, old.slot_id, true)
      if old.visible_overlay_id ~= nil then
        -- Orphaned: keep the node so its overlay can be retired gracefully.
        old.status = "orphaned"
        next_nodes[node_id] = old
        next_order[#next_order + 1] = node_id
      end
      -- deleted_confirmed nodes (no visible overlay) are dropped entirely;
      -- they can never be matched again and only bloat the state.
    end
  end

  buf.nodes = next_nodes
  buf.node_order = next_order

  for _, node_id in ipairs(next_order) do
    local node = next_nodes[node_id]
    if moved_visible_nodes[node.node_id] or node_needs_overlay_binding_refresh(new_state, node, ev) then
      effects[#effects + 1] = {
        kind = "bind_overlay",
        overlay_id = node.visible_overlay_id,
        request_id = new_state.overlays[node.visible_overlay_id].request_id,
        node_id = node.node_id,
        bufnr = node.bufnr,
        buffer_version = ev.buffer_version,
        layout_version = ev.layout_version,
        display_range = copy_range(node.display_range),
        semantics = deepcopy(node.semantics),
      }
    end
  end

  return new_state, effects
end

local function reduce_full_render_requested(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local buf = new_state.buffers[ev.bufnr]
  if buf == nil then
    return new_state, effects
  end

  retire_orphans_covered_by_visible_nodes(new_state, buf, effects)
  retire_orphans_without_replacement(new_state, buf, effects)
  ensure_slot_registry(buf)

  local has_dirty = false
  local request_slot_ids = {}
  for _, slot_id in ipairs(buf.slot_order or {}) do
    local slot = buf.slots[slot_id]
    if slot ~= nil then
      request_slot_ids[#request_slot_ids + 1] = slot_id
      if slot.status == "dirty" or slot.dirty == true then
        has_dirty = true
      end
    end
  end
  if not has_dirty then
    abandon_idle_request(new_state, buf, effects)
    return new_state, effects
  end

  buf.render_epoch = (buf.render_epoch or 0) + 1
  local request_id = next_id(new_state.counters, "next_request_id", "request:")
  retire_old_request_candidates(new_state, buf, buf.active_request_id, effects, request_id)
  buf.active_request_id = request_id

  local jobs = {}
  for _, slot_id in ipairs(request_slot_ids) do
    local slot = buf.slots[slot_id]
    if slot.status == "tombstone" then
      if slot.dirty == true then
        slot.pending_request_id = request_id
      end
      jobs[#jobs + 1] = render_tombstone_stub(slot)
    else
      local node = slot.node_id and buf.nodes[slot.node_id] or nil
      if node ~= nil and node.status ~= "orphaned" and node.status ~= "deleted_confirmed" then
        local dirty = slot.status == "dirty" or slot.dirty == true or should_rerender_node(node)
        if dirty then
          local overlay = new_overlay(new_state, buf, node, request_id, slot.page_index, slot.slot_id)
          node.candidate_overlay_id = overlay.overlay_id
          node.status = "pending"
          slot.candidate_overlay_id = overlay.overlay_id
          slot.pending_request_id = request_id
          slot.status = "dirty"
          slot.dirty = true
          jobs[#jobs + 1] = render_job_from_node(node, overlay)

          if node.visible_overlay_id == nil then
            effects[#effects + 1] = {
              kind = "ensure_overlay_placeholder",
              overlay_id = overlay.overlay_id,
              bufnr = buf.bufnr,
              node_id = node.node_id,
              display_range = copy_range(node.display_range),
              semantics = deepcopy(node.semantics),
            }
          end
        else
          jobs[#jobs + 1] = render_stub_from_node(node, slot)
        end
      else
        slot.status = "tombstone"
        slot.dirty = true
        slot.pending_request_id = request_id
        jobs[#jobs + 1] = render_tombstone_stub(slot)
      end
    end
  end

  effects[#effects + 1] = {
    kind = "request_full_render",
    request = {
      request_id = request_id,
      bufnr = buf.bufnr,
      project_scope_id = buf.project_scope_id,
      render_epoch = buf.render_epoch,
      buffer_version = buf.buffer_version,
      layout_version = buf.layout_version,
      shape_epoch = buf.shape_epoch or 0,
      jobs = jobs,
    },
  }

  return new_state, effects
end

local function reduce_formula_renders_requested(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local buf = new_state.buffers[ev.bufnr]
  if buf == nil then
    return new_state, effects
  end

  retire_orphans_covered_by_visible_nodes(new_state, buf, effects)
  retire_orphans_without_replacement(new_state, buf, effects)
  ensure_slot_registry(buf)

  local jobs = {}
  local requested = ev.node_ids
  local requested_set = nil
  local request_slot_ids = nil
  if type(requested) == "table" then
    requested_set = {}
    request_slot_ids = {}
    local seen_slots = {}
    for _, node_id in ipairs(requested) do
      requested_set[node_id] = true
      local node = buf.nodes[node_id]
      local slot_id = node and node.slot_id or nil
      if slot_id ~= nil and not seen_slots[slot_id] then
        request_slot_ids[#request_slot_ids + 1] = slot_id
        seen_slots[slot_id] = true
      end
    end
  end
  request_slot_ids = request_slot_ids or buf.slot_order or {}

  local request_id = nil
  local function ensure_request_id()
    if request_id == nil then
      buf.render_epoch = (buf.render_epoch or 0) + 1
      request_id = ev.request_id or next_id(new_state.counters, "next_request_id", "formula:")
    end
    return request_id
  end

  for _, slot_id in ipairs(request_slot_ids) do
    local slot = buf.slots[slot_id]
    if slot ~= nil then
      if slot.status == "tombstone" then
        slot.pending_request_id = nil
        slot.dirty = false
      else
        local node = slot.node_id and buf.nodes[slot.node_id] or nil
        if
          node ~= nil
          and node.status ~= "orphaned"
          and node.status ~= "deleted_confirmed"
          and (requested_set == nil or requested_set[node.node_id])
        then
          local dirty = slot.status == "dirty" or slot.dirty == true or should_rerender_node(node)
          if dirty then
            if pending_candidate_matches_node(new_state, buf, node) then
              local overlay = new_state.overlays[node.candidate_overlay_id]
              node.status = "pending"
              node.pending_request_id = overlay.request_id
              slot.candidate_overlay_id = overlay.overlay_id
              slot.pending_request_id = overlay.request_id
              slot.status = "dirty"
              slot.dirty = true
              goto continue_slot
            end

            retire_node_candidate(new_state, node, effects)

            local current_request_id = ensure_request_id()
            local overlay = new_overlay(new_state, buf, node, current_request_id, slot.page_index, slot.slot_id)
            node.candidate_overlay_id = overlay.overlay_id
            node.status = "pending"
            node.pending_request_id = current_request_id
            slot.candidate_overlay_id = overlay.overlay_id
            slot.pending_request_id = current_request_id
            slot.status = "dirty"
            slot.dirty = true
            jobs[#jobs + 1] = render_job_from_node(node, overlay)

            if node.visible_overlay_id == nil then
              effects[#effects + 1] = {
                kind = "ensure_overlay_placeholder",
                overlay_id = overlay.overlay_id,
                bufnr = buf.bufnr,
                node_id = node.node_id,
                display_range = copy_range(node.display_range),
                semantics = deepcopy(node.semantics),
              }
            end
          end
        end
      end
      ::continue_slot::
    end
  end

  if #jobs > 0 then
    effects[#effects + 1] = {
      kind = "request_formula_render_batch",
      request = {
        request_id = request_id,
        bufnr = buf.bufnr,
        project_scope_id = buf.project_scope_id,
        render_epoch = buf.render_epoch,
        buffer_version = buf.buffer_version,
        layout_version = buf.layout_version,
        shape_epoch = buf.shape_epoch or 0,
        jobs = jobs,
      },
    }
  end

  return new_state, effects
end

local function reduce_overlay_page_ready(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local overlay = new_state.overlays[ev.overlay_id]
  if overlay == nil then
    return new_state, effects
  end

  local buf = new_state.buffers[overlay.owner_bufnr]
  if buf == nil then
    return new_state, effects
  end

  local node = buf.nodes[overlay.owner_node_id]
  if node == nil then
    return new_state, effects
  end

  if overlay.request_id ~= ev.request_id then
    return new_state, effects
  end
  if overlay.page_index ~= nil and overlay.page_index ~= ev.request_page_index then
    return new_state, effects
  end

  if overlay.owner_node_id ~= ev.owner_node_id then
    return new_state, effects
  end
  if overlay.owner_bufnr ~= ev.owner_bufnr then
    return new_state, effects
  end
  if overlay.owner_project_scope_id ~= ev.owner_project_scope_id then
    return new_state, effects
  end

  if overlay.render_epoch ~= ev.render_epoch then
    return new_state, effects
  end
  if ev.node_rev ~= nil and overlay.node_rev ~= ev.node_rev then
    return new_state, effects
  end
  if ev.context_id ~= nil and overlay.context_id ~= ev.context_id then
    return new_state, effects
  end
  if ev.context_rev ~= nil and overlay.context_rev ~= ev.context_rev then
    return new_state, effects
  end
  if overlay.buffer_version ~= ev.buffer_version then
    return new_state, effects
  end
  if overlay.layout_version ~= ev.layout_version then
    return new_state, effects
  end

  if node.candidate_overlay_id ~= overlay.overlay_id then
    return new_state, effects
  end

  overlay.page_path = ev.page_path
  overlay.page_stamp = ev.page_stamp
  overlay.natural_cols = ev.natural_cols
  overlay.natural_rows = ev.natural_rows
  overlay.source_rows = ev.source_rows
  overlay.status = "ready"
  node.status = "ready"

  effects[#effects + 1] = {
    kind = "commit_overlay",
    overlay_id = overlay.overlay_id,
    node_id = node.node_id,
    bufnr = buf.bufnr,
    page_path = ev.page_path,
    natural_cols = ev.natural_cols,
    natural_rows = ev.natural_rows,
    source_rows = ev.source_rows,
  }

  return new_state, effects
end

local function reduce_overlay_resources_allocated(state, ev)
  local new_state = clone_state(state)
  local overlay = new_state.overlays[ev.overlay_id]
  if overlay == nil then
    return new_state, {}
  end

  overlay.image_id = ev.image_id
  overlay.extmark_id = ev.extmark_id
  if ev.binding_display_range ~= nil then
    record_overlay_binding(overlay, ev.binding_buffer_version, ev.binding_layout_version, ev.binding_display_range)
  end
  return new_state, {}
end

local function reduce_overlay_commit_succeeded(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local overlay = new_state.overlays[ev.overlay_id]
  if overlay == nil or overlay.owner_node_id ~= ev.node_id then
    return new_state, effects
  end

  local buf = new_state.buffers[overlay.owner_bufnr]
  if buf == nil then
    return new_state, effects
  end

  local node = buf.nodes[overlay.owner_node_id]
  if node == nil or node.candidate_overlay_id ~= overlay.overlay_id then
    return new_state, effects
  end

  local old_visible_id = node.visible_overlay_id
  overlay.status = "visible"
  node.visible_overlay_id = overlay.overlay_id
  node.candidate_overlay_id = nil
  node.status = "stable"
  node.last_rendered_epoch = overlay.render_epoch
  node.last_buffer_version = overlay.buffer_version
  node.last_layout_version = overlay.layout_version
  mark_slot_committed(buf, node, overlay)

  if old_visible_id ~= nil and old_visible_id ~= overlay.overlay_id then
    local old_overlay = new_state.overlays[old_visible_id]
    if old_overlay ~= nil then
      old_overlay.status = "retiring"
      effects[#effects + 1] = {
        kind = "retire_overlay",
        overlay_id = old_visible_id,
      }
    end
  end
  retire_overlapping_orphans(new_state, buf, node, effects)
  if
    buf.active_request_id == overlay.request_id and not request_has_pending_overlay(new_state, buf, overlay.request_id)
  then
    buf.active_request_id = nil
  end

  return new_state, effects
end

local function reduce_buffer_layout_changed(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local buf = new_state.buffers[ev.bufnr]
  if buf == nil then
    return new_state, effects
  end

  buf.layout_version = ev.new_layout_version
  ensure_slot_registry(buf)
  for _, node_id in ipairs(buf.node_order or {}) do
    local node = buf.nodes[node_id]
    if
      node ~= nil
      and node.status ~= "orphaned"
      and node.status ~= "deleted_confirmed"
      and node.visible_overlay_id ~= nil
    then
      local overlay = new_state.overlays[node.visible_overlay_id]
      if overlay_can_bind_without_render(overlay) then
        effects[#effects + 1] = {
          kind = "bind_overlay",
          overlay_id = overlay.overlay_id,
          request_id = overlay.request_id,
          node_id = node.node_id,
          bufnr = node.bufnr,
          buffer_version = buf.buffer_version,
          layout_version = ev.new_layout_version,
          display_range = copy_range(node.display_range),
          semantics = deepcopy(node.semantics),
        }
      end
    end
  end

  return new_state, effects
end

local function reduce_request_abandoned(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  for _, overlay in pairs(new_state.overlays or {}) do
    if overlay.owner_bufnr == ev.bufnr and overlay.request_id == ev.request_id and overlay.status ~= "visible" then
      overlay.status = "retiring"
      effects[#effects + 1] = {
        kind = "retire_overlay",
        overlay_id = overlay.overlay_id,
      }
    end
  end

  local buf = new_state.buffers[ev.bufnr]
  if buf ~= nil then
    if buf.active_request_id == ev.request_id then
      buf.active_request_id = nil
    end
    ensure_slot_registry(buf)
    for _, node in pairs(buf.nodes or {}) do
      local candidate = node.candidate_overlay_id and new_state.overlays[node.candidate_overlay_id] or nil
      if candidate ~= nil and candidate.request_id == ev.request_id then
        node.candidate_overlay_id = nil
        if node.status ~= "orphaned" and node.status ~= "deleted_confirmed" then
          node.status = node.visible_overlay_id ~= nil and "stale" or "pending"
        end
      end
    end
    for _, slot in pairs(buf.slots or {}) do
      if slot.pending_request_id == ev.request_id then
        slot.pending_request_id = nil
        slot.candidate_overlay_id = nil
        if slot.status == "tombstone" then
          slot.dirty = true
        else
          slot.status = "dirty"
          slot.dirty = true
        end
      end
    end
  end

  return new_state, effects
end

local function reduce_overlay_pages_batch_ready(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  for _, entry in ipairs(ev.entries or {}) do
    local overlay = new_state.overlays[entry.overlay_id]
    if overlay == nil then
      goto continue_entry
    end

    local buf = new_state.buffers[overlay.owner_bufnr]
    if buf == nil then
      goto continue_entry
    end

    local node = buf.nodes[overlay.owner_node_id]
    if node == nil then
      goto continue_entry
    end

    if overlay.request_id ~= entry.request_id then
      goto continue_entry
    end
    if overlay.page_index ~= nil and overlay.page_index ~= entry.request_page_index then
      goto continue_entry
    end
    if overlay.owner_node_id ~= entry.owner_node_id then
      goto continue_entry
    end
    if overlay.owner_bufnr ~= entry.owner_bufnr then
      goto continue_entry
    end
    if overlay.owner_project_scope_id ~= entry.owner_project_scope_id then
      goto continue_entry
    end
    if overlay.render_epoch ~= entry.render_epoch then
      goto continue_entry
    end
    if entry.node_rev ~= nil and overlay.node_rev ~= entry.node_rev then
      goto continue_entry
    end
    if entry.context_id ~= nil and overlay.context_id ~= entry.context_id then
      goto continue_entry
    end
    if entry.context_rev ~= nil and overlay.context_rev ~= entry.context_rev then
      goto continue_entry
    end
    if overlay.buffer_version ~= entry.buffer_version then
      goto continue_entry
    end
    if overlay.layout_version ~= entry.layout_version then
      goto continue_entry
    end
    if node.candidate_overlay_id ~= overlay.overlay_id then
      goto continue_entry
    end

    overlay.page_path = entry.page_path
    overlay.page_stamp = entry.page_stamp
    overlay.natural_cols = entry.natural_cols
    overlay.natural_rows = entry.natural_rows
    overlay.source_rows = entry.source_rows
    overlay.status = "ready"
    node.status = "ready"

    effects[#effects + 1] = {
      kind = "commit_overlay",
      overlay_id = overlay.overlay_id,
      node_id = node.node_id,
      bufnr = buf.bufnr,
      page_path = entry.page_path,
      natural_cols = entry.natural_cols,
      natural_rows = entry.natural_rows,
      source_rows = entry.source_rows,
    }

    ::continue_entry::
  end

  return new_state, effects
end

local function reduce_overlay_render_failed(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local overlay = new_state.overlays[ev.overlay_id]
  if overlay == nil then
    return new_state, effects
  end
  local buf = new_state.buffers[overlay.owner_bufnr]
  if buf == nil then
    return new_state, effects
  end
  local node = buf.nodes[overlay.owner_node_id]
  if node == nil then
    return new_state, effects
  end

  if overlay.request_id ~= ev.request_id then
    return new_state, effects
  end
  if ev.node_rev ~= nil and overlay.node_rev ~= ev.node_rev then
    return new_state, effects
  end
  if ev.context_id ~= nil and overlay.context_id ~= ev.context_id then
    return new_state, effects
  end
  if ev.context_rev ~= nil and overlay.context_rev ~= ev.context_rev then
    return new_state, effects
  end
  if node.candidate_overlay_id ~= overlay.overlay_id then
    return new_state, effects
  end

  overlay.status = "retiring"
  node.candidate_overlay_id = nil
  if node.status ~= "orphaned" and node.status ~= "deleted_confirmed" then
    node.status = node.visible_overlay_id ~= nil and "stale" or "pending"
  end

  ensure_slot_registry(buf)
  local slot = node.slot_id and buf.slots[node.slot_id] or nil
  if slot ~= nil and slot.pending_request_id == ev.request_id then
    slot.pending_request_id = nil
    slot.candidate_overlay_id = nil
    slot.status = "dirty"
    slot.dirty = true
  end

  effects[#effects + 1] = {
    kind = "retire_overlay",
    overlay_id = overlay.overlay_id,
  }

  return new_state, effects
end

local function reduce_overlay_commits_batch_succeeded(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  for _, entry in ipairs(ev.entries or {}) do
    local overlay = new_state.overlays[entry.overlay_id]
    if overlay == nil or overlay.owner_node_id ~= entry.node_id then
      goto continue_commit
    end

    local buf = new_state.buffers[overlay.owner_bufnr]
    if buf == nil then
      goto continue_commit
    end

    local node = buf.nodes[overlay.owner_node_id]
    if node == nil or node.candidate_overlay_id ~= overlay.overlay_id then
      goto continue_commit
    end

    local old_visible_id = node.visible_overlay_id
    overlay.status = "visible"
    node.visible_overlay_id = overlay.overlay_id
    node.candidate_overlay_id = nil
    node.status = "stable"
    node.last_rendered_epoch = overlay.render_epoch
    node.last_buffer_version = overlay.buffer_version
    node.last_layout_version = overlay.layout_version
    mark_slot_committed(buf, node, overlay)

    if old_visible_id ~= nil and old_visible_id ~= overlay.overlay_id then
      local old_overlay = new_state.overlays[old_visible_id]
      if old_overlay ~= nil then
        old_overlay.status = "retiring"
        effects[#effects + 1] = {
          kind = "retire_overlay",
          overlay_id = old_visible_id,
        }
      end
    end
    retire_overlapping_orphans(new_state, buf, node, effects)
    if
      buf.active_request_id == overlay.request_id
      and not request_has_pending_overlay(new_state, buf, overlay.request_id)
    then
      buf.active_request_id = nil
    end

    ::continue_commit::
  end

  return new_state, effects
end

local function reduce_render_request_completed(state, ev)
  local new_state = clone_state(state)
  local buf = new_state.buffers[ev.bufnr]
  if buf == nil then
    return new_state, {}
  end

  ensure_slot_registry(buf)
  for _, slot in pairs(buf.slots or {}) do
    if slot.pending_request_id == ev.request_id and slot.status == "tombstone" then
      slot.pending_request_id = nil
      slot.dirty = false
    end
  end

  if buf.active_request_id == ev.request_id and not request_has_pending_overlay(new_state, buf, ev.request_id) then
    buf.active_request_id = nil
  end

  return new_state, {}
end

local function reduce_overlay_bindings_batch_succeeded(state, ev)
  local new_state = clone_state(state)

  for _, entry in ipairs(ev.entries or {}) do
    local overlay = new_state.overlays[entry.overlay_id]
    if overlay == nil or overlay.owner_node_id ~= entry.node_id or overlay.request_id ~= entry.request_id then
      goto continue_binding
    end

    local buf = new_state.buffers[overlay.owner_bufnr]
    if buf == nil or buf.bufnr ~= entry.bufnr then
      goto continue_binding
    end
    if buf.buffer_version ~= entry.buffer_version or buf.layout_version ~= entry.layout_version then
      goto continue_binding
    end

    local node = buf.nodes[overlay.owner_node_id]
    if
      node == nil
      or node.visible_overlay_id ~= overlay.overlay_id
      or not ranges_equal(node.display_range, entry.display_range)
    then
      goto continue_binding
    end

    overlay.extmark_id = entry.extmark_id or overlay.extmark_id
    record_overlay_binding(overlay, entry.buffer_version, entry.layout_version, entry.display_range)

    ::continue_binding::
  end

  return new_state, {}
end

local function reduce_visible_overlay_lost(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local overlay = new_state.overlays[ev.overlay_id]
  if overlay == nil then
    return new_state, effects
  end

  local buf = new_state.buffers[overlay.owner_bufnr]
  if buf == nil or (ev.bufnr ~= nil and buf.bufnr ~= ev.bufnr) then
    return new_state, effects
  end

  local node = buf.nodes[overlay.owner_node_id]
  if node == nil or (ev.node_id ~= nil and node.node_id ~= ev.node_id) then
    return new_state, effects
  end
  if node.visible_overlay_id ~= overlay.overlay_id then
    return new_state, effects
  end

  overlay.status = "retiring"
  node.visible_overlay_id = nil
  if node.status ~= "orphaned" and node.status ~= "deleted_confirmed" then
    node.status = node.candidate_overlay_id ~= nil and "stale" or "pending"
  end

  ensure_slot_registry(buf)
  local slot = node.slot_id and buf.slots[node.slot_id] or nil
  if slot ~= nil then
    slot.visible_overlay_id = nil
    slot.status = "dirty"
    slot.dirty = true
    slot.candidate_overlay_id = node.candidate_overlay_id
    local candidate = node.candidate_overlay_id and new_state.overlays[node.candidate_overlay_id] or nil
    slot.pending_request_id = candidate and candidate.request_id or nil
  end

  effects[#effects + 1] = {
    kind = "retire_overlay",
    overlay_id = overlay.overlay_id,
  }

  return new_state, effects
end

local function reduce_node_deleted_confirmed(state, ev)
  local new_state = clone_state(state)
  local effects = {}

  local buf = new_state.buffers[ev.bufnr]
  if buf == nil then
    return new_state, effects
  end

  local node = buf.nodes[ev.node_id]
  if node == nil then
    return new_state, effects
  end

  local old_visible_id = node.visible_overlay_id
  node.status = "deleted_confirmed"
  node.candidate_overlay_id = nil
  node.visible_overlay_id = nil
  tombstone_slot(buf, node.slot_id, true)

  if old_visible_id ~= nil then
    local overlay = new_state.overlays[old_visible_id]
    if overlay ~= nil and overlay.status ~= "retired" then
      overlay.status = "retiring"
      effects[#effects + 1] = {
        kind = "retire_overlay",
        overlay_id = old_visible_id,
      }
    end
  end

  return new_state, effects
end

function M.reduce(state, event)
  if event.type == "nodes_scanned" then
    return reduce_nodes_scanned(state, event)
  elseif event.type == "full_render_requested" then
    return reduce_full_render_requested(state, event)
  elseif event.type == "formula_renders_requested" then
    return reduce_formula_renders_requested(state, event)
  elseif event.type == "overlay_page_ready" then
    return reduce_overlay_page_ready(state, event)
  elseif event.type == "overlay_resources_allocated" then
    return reduce_overlay_resources_allocated(state, event)
  elseif event.type == "overlay_commit_succeeded" then
    return reduce_overlay_commit_succeeded(state, event)
  elseif event.type == "overlay_pages_batch_ready" then
    return reduce_overlay_pages_batch_ready(state, event)
  elseif event.type == "overlay_render_failed" then
    return reduce_overlay_render_failed(state, event)
  elseif event.type == "overlay_commits_batch_succeeded" then
    return reduce_overlay_commits_batch_succeeded(state, event)
  elseif event.type == "render_request_completed" then
    return reduce_render_request_completed(state, event)
  elseif event.type == "overlay_bindings_batch_succeeded" then
    return reduce_overlay_bindings_batch_succeeded(state, event)
  elseif event.type == "visible_overlay_lost" then
    return reduce_visible_overlay_lost(state, event)
  elseif event.type == "buffer_layout_changed" then
    return reduce_buffer_layout_changed(state, event)
  elseif
    event.type == "request_abandoned"
    or event.type == "render_request_failed"
    or event.type == "render_request_superseded"
  then
    return reduce_request_abandoned(state, event)
  elseif event.type == "node_deleted_confirmed" then
    return reduce_node_deleted_confirmed(state, event)
  end

  return state or types.initial_state(), {}
end

M._clone_state = clone_state

return M
