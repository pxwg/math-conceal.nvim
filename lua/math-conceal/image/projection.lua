local context = require("math-conceal.image.context")
local grid = require("math-conceal.image.grid")
local placement = require("math-conceal.image.placement")
local quickfix = require("math-conceal.image.quickfix")
local realization_common = require("math-conceal.image.realization.common")
local realization_registry = require("math-conceal.image.realization")
local repair_event = require("math-conceal.image.repair-event")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")
local tracker = require("math-conceal.image.tracker")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function active_windows(bufnr)
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      wins[#wins + 1] = winid
    end
  end
  table.sort(wins)
  return wins
end

local function window_set_key(wins)
  return table.concat(wins or {}, ",")
end

local function window_viewport(winid)
  local ok, viewport = pcall(vim.api.nvim_win_call, winid, function()
    return { top = vim.fn.line("w0") - 1, bottom = vim.fn.line("w$") - 1 }
  end)
  if not ok or type(viewport) ~= "table" then
    return nil
  end
  return viewport
end

local function priority_before(left, right)
  for _, field in ipairs({ "outside", "distance", "row", "col" }) do
    if left[field] ~= right[field] then
      return left[field] < right[field]
    end
  end
  return left.key < right.key
end

local function track_priority(key, track, viewports)
  local distance = math.huge
  for _, viewport in ipairs(viewports) do
    if track.end_row >= viewport.top and track.row <= viewport.bottom then
      distance = 0
      break
    elseif track.end_row < viewport.top then
      distance = math.min(distance, viewport.top - track.end_row)
    else
      distance = math.min(distance, track.row - viewport.bottom)
    end
  end
  return {
    outside = distance == 0 and 0 or 1,
    distance = distance,
    row = track.row or 0,
    col = track.col or 0,
    key = key,
  }
end

local function ordered_tracks(tracks_by_key, wins)
  local viewports = {}
  for _, winid in ipairs(wins) do
    local viewport = window_viewport(winid)
    if viewport ~= nil then
      viewports[#viewports + 1] = viewport
    end
  end
  local ordered = {}
  for key, track in pairs(tracks_by_key or {}) do
    ordered[#ordered + 1] = { key = key, track = track, priority = track_priority(key, track, viewports) }
  end
  table.sort(ordered, function(left, right)
    return priority_before(left.priority, right.priority)
  end)
  return ordered
end

local function request_id(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.next_request_id = (bs.next_request_id or 0) + 1
  return ("image:%d:%d"):format(bufnr, bs.next_request_id)
end

local function next_token(bs)
  bs.next_realization_token = (bs.next_realization_token or 0) + 1
  return bs.next_realization_token
end

local function ensure_projection(bs, bufnr, track)
  local key = tracker.track_ref_key(track)
  local projection = bs.projections[key]
  if projection == nil then
    projection = {
      bufnr = bufnr,
      key = key,
      ref = realization_common.ref(track),
      realizations = {},
      pending = {},
      failed = {},
      desired_keys = {},
    }
    bs.projections[key] = projection
  end
  projection.ref = realization_common.ref(track)
  return projection
end

local function release_asset(asset)
  if asset == nil or asset.image_id == nil then
    return
  end
  placement.release_image(asset.image_id)
  terminal.delete_image(asset.image_id)
end

local function newest_asset(projection)
  local newest = nil
  for _, asset in pairs(projection.realizations or {}) do
    if newest == nil or (asset.last_used or 0) > (newest.last_used or 0) then
      newest = asset
    end
  end
  return newest
end

local function close_projection_assets(projection)
  for key, asset in pairs(projection.realizations or {}) do
    release_asset(asset)
    projection.realizations[key] = nil
  end
  projection.visible_asset = nil
  projection.pending = {}
  projection.failed = {}
  projection.desired_keys = {}
end

local function cleanup_projection(projection)
  close_projection_assets(projection)
  projection.status = "retired"
end

local function touch_asset(bs, projection, asset)
  bs.realization_clock = (bs.realization_clock or 0) + 1
  asset.last_used = bs.realization_clock
  projection.visible_asset = asset
end

local function evict_inactive_realizations(bs, projection)
  local inactive = {}
  for key, asset in pairs(projection.realizations or {}) do
    if projection.desired_keys[key] ~= true then
      inactive[#inactive + 1] = { key = key, asset = asset }
    end
  end
  table.sort(inactive, function(left, right)
    return (left.asset.last_used or 0) > (right.asset.last_used or 0)
  end)
  for index = 2, #inactive do
    local item = inactive[index]
    release_asset(item.asset)
    projection.realizations[item.key] = nil
  end
  if projection.visible_asset ~= nil and projection.realizations[projection.visible_asset.key] == nil then
    projection.visible_asset = newest_asset(projection)
  end
  for key in pairs(projection.pending or {}) do
    if projection.desired_keys[key] ~= true then
      projection.pending[key] = nil
    end
  end
  for key in pairs(projection.failed or {}) do
    if projection.desired_keys[key] ~= true then
      projection.failed[key] = nil
    end
  end
end

local function adapter_for(binding)
  local name = binding and (binding.source_kind or binding.scanner or binding.kind) or nil
  return name, realization_registry.require(name)
end

local function source_request(track, reason)
  return {
    state = "source",
    ref = realization_common.ref(track),
    reason = reason,
  }
end

local function map_generated_pos(line_map, line, col)
  if line_map == nil or line < line_map.gen_start or line > line_map.gen_end then
    return nil
  end
  local line_offset = line - line_map.gen_start
  return {
    filename = vim.api.nvim_buf_get_name(line_map.bufnr),
    lnum = line_map.src_start + line_offset,
    col = line_map.src_start == line_map.src_end
        and math.min(line_map.src_end_col, line_map.src_start_col + math.max(0, col - line_map.gen_start_col))
      or col,
  }
end

local function diagnostic_items(bufnr, diagnostics, line_map, prefix)
  local items = {}
  for _, diag in ipairs(diagnostics or {}) do
    local line = tonumber(diag.line) or 1
    local col = tonumber(diag.column) or 1
    local filename = diag.file
    local mapped = map_generated_pos(line_map, line, col)
    if mapped ~= nil and (filename == nil or tostring(filename):find("/__typst_concealer__/", 1, true) ~= nil) then
      filename, line, col = mapped.filename, mapped.lnum, mapped.col
    elseif filename == nil or filename == "" then
      filename = vim.api.nvim_buf_get_name(bufnr)
    end
    items[#items + 1] = {
      filename = filename,
      lnum = line,
      col = col,
      text = prefix .. tostring(diag.message or "render error"),
      type = diag.severity == "warning" and "W" or "E",
    }
  end
  return items
end

local function update_diagnostics(bufnr, node_id, descriptor, accepted)
  local line_map = accepted.line_map or (descriptor.meta and descriptor.meta.line_map) or nil
  quickfix.set_items(
    bufnr,
    "formula_by_node",
    node_id,
    diagnostic_items(bufnr, accepted.diagnostics, line_map, "[service/formula] ")
  )
  if descriptor.batch_kind ~= "code_flow" then
    return
  end
  local flow_items = diagnostic_items(bufnr, accepted.flow_diagnostics, nil, "[service/flow] ")
  if accepted.flow_status ~= "ok" and #flow_items == 0 then
    local track = tracker.resolve_ref(descriptor.meta and descriptor.meta.ref or nil)
    flow_items[1] = {
      filename = vim.api.nvim_buf_get_name(bufnr),
      lnum = track and track.row + 1 or 1,
      col = track and track.col + 1 or 1,
      text = "[service/flow] failed to classify Typst code layout; showing source",
      type = "W",
    }
  end
  quickfix.set_items(bufnr, "flow_by_node", node_id, flow_items)
end

local function prune_projection_table(bs, tracks_by_key)
  for key, projection in pairs(bs.projections or {}) do
    if tracks_by_key[key] == nil then
      cleanup_projection(projection)
      bs.projections[key] = nil
    end
  end
end

local function batch_key(adapter_name, descriptor)
  return table.concat({ adapter_name, descriptor.batch_kind, descriptor.layout_key or "shared" }, "\0")
end

local function add_to_batch(batches, adapter_name, descriptor, priority)
  local key = batch_key(adapter_name, descriptor)
  local batch = batches[key]
  if batch == nil then
    batch = {
      key = key,
      adapter_name = adapter_name,
      kind = descriptor.batch_kind,
      layout = descriptor.layout,
      descriptors = {},
      priority = priority,
    }
    batches[key] = batch
  elseif priority_before(priority, batch.priority) then
    batch.priority = priority
  end
  batch.descriptors[#batch.descriptors + 1] = descriptor
end

local function ordered_batches(batches)
  local ordered = vim.tbl_values(batches or {})
  table.sort(ordered, function(left, right)
    if priority_before(left.priority, right.priority) then
      return true
    end
    if priority_before(right.priority, left.priority) then
      return false
    end
    return left.key < right.key
  end)
  return ordered
end

local function queue_descriptor(bs, batches, adapter_name, projection, descriptor, priority)
  if
    projection.realizations[descriptor.key] ~= nil
    or projection.pending[descriptor.key] ~= nil
    or projection.failed[descriptor.key] == true
  then
    return
  end
  local token = next_token(bs)
  descriptor.pending_token = token
  descriptor.meta.pending_token = token
  projection.pending[descriptor.key] = { token = token, descriptor = descriptor }
  add_to_batch(batches, adapter_name, descriptor, priority)
end

local function dispatch_batches(bufnr, binding, adapter, batches, ctx, config, on_failure)
  for _, batch in ipairs(ordered_batches(batches)) do
    batch.request_id = request_id(bufnr)
    batch.context = ctx
    batch.config = config
    if not adapter.dispatch_batch(bufnr, binding, batch) then
      local bs = state.get_buf_state(bufnr)
      for _, descriptor in ipairs(batch.descriptors) do
        local projection = bs.projections[descriptor.meta.projection_key]
        local pending = projection and projection.pending[descriptor.key] or nil
        if pending ~= nil and pending.token == descriptor.pending_token then
          projection.pending[descriptor.key] = nil
          projection.failed[descriptor.key] = true
        end
      end
      if on_failure ~= nil then
        on_failure()
      end
    end
  end
end

local function descriptor_for(projection, track, adapter, ctx, window_ctx, config)
  local layout = adapter.layout(track, window_ctx, ctx, config)
  return adapter.describe(track, ctx, layout, config, projection.key)
end

local function request_for_demand(bs, projection, track, adapter, descriptor, config)
  local asset = projection and projection.realizations[descriptor.key] or nil
  if asset ~= nil then
    touch_asset(bs, projection, asset)
    return adapter.placement_request(asset, track, config)
  end
  if descriptor.pending_visibility == "previous" and projection and projection.visible_asset ~= nil then
    touch_asset(bs, projection, projection.visible_asset)
    return adapter.placement_request(projection.visible_asset, track, config)
  end
  return source_request(track, projection and projection.failed[descriptor.key] and "failed" or "pending")
end

local function place_windows(bufnr, wins, bs, tracks_by_key, adapter, desired_by_win, config)
  local active = {}
  for _, winid in ipairs(wins) do
    active[winid] = true
  end
  for winid in pairs(bs.placement_windows or {}) do
    if not active[winid] then
      placement.close_window(winid, bufnr)
      bs.window_placement_keys[winid] = nil
      bs.window_realization_keys[winid] = nil
    end
  end

  for _, winid in ipairs(wins) do
    local previous = bs.window_placement_keys[winid] or {}
    local current = {}
    local realization_keys = {}
    local transaction = { upsert = {}, close = {}, conceal_in_normal = config.conceal_in_normal == true }
    for key, demand in pairs(desired_by_win[winid] or {}) do
      current[key] = true
      realization_keys[key] = demand.descriptor.key
      local projection = bs.projections[key]
      local track = tracks_by_key[key]
      local request = request_for_demand(bs, projection, track, adapter, demand.descriptor, config)
      transaction.upsert[key] = request or source_request(track, "unavailable")
    end
    for key in pairs(previous) do
      if not current[key] then
        transaction.close[key] = true
      end
    end
    placement.reconcile_window(winid, transaction)
    bs.window_placement_keys[winid] = current
    bs.window_realization_keys[winid] = realization_keys
  end
  bs.placement_windows = active
  bs.placement_window_key = window_set_key(wins)
end

local function wanted_realizations(bs)
  local wanted = {}
  for _, projection in pairs(bs.projections or {}) do
    for key in pairs(projection.desired_keys or {}) do
      wanted[key] = true
    end
  end
  return wanted
end

local function repair_track_keys(event)
  local keys = repair_event.ref_set(event.checked_refs)
  repair_event.merge_keys(keys, repair_event.ref_set(event.born_refs))
  repair_event.merge_keys(keys, repair_event.context_dependent_key_set(event))
  return keys
end

local function sync_repair(event)
  local bufnr = event.bufnr
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local adapter_name, adapter = adapter_for(binding)
  local bs = state.get_buf_state(bufnr)
  bs.window_placement_keys = bs.window_placement_keys or {}
  bs.window_realization_keys = bs.window_realization_keys or {}
  bs.placement_windows = bs.placement_windows or {}
  local ctx = context.resolve(bufnr, binding, event.context, image.config)
  bs.context = ctx
  local tracks_by_key = repair_event.tracks_by_key(event)
  local keys = repair_track_keys(event)
  local affected = {}
  for key in pairs(keys) do
    local track = tracks_by_key[key]
    if track ~= nil and track.state == "valid" and track.invalid ~= true then
      affected[key] = track
      ensure_projection(bs, bufnr, track)
    end
  end

  local retired = repair_event.ref_set(event.retired_refs)
  for key in pairs(retired) do
    local projection = bs.projections[key]
    if projection ~= nil then
      cleanup_projection(projection)
      bs.projections[key] = nil
    end
  end
  if next(affected) == nil and next(retired) == nil then
    return
  end

  local wins = active_windows(bufnr)
  local tracks = ordered_tracks(affected, wins)
  local geometry = repair_event.ref_set(event.geometry_changed_refs)
  local batches = {}
  local desired = {}
  local transactions = {}
  for _, item in ipairs(tracks) do
    desired[item.key] = {}
  end
  for _, winid in ipairs(wins) do
    local window_ctx = realization_common.window_context(winid, image.config)
    local transaction = {
      upsert = {},
      close = vim.deepcopy(retired),
      refresh = {},
      conceal_in_normal = image.config.conceal_in_normal == true,
    }
    transactions[winid] = transaction
    bs.window_placement_keys[winid] = bs.window_placement_keys[winid] or {}
    bs.window_realization_keys[winid] = bs.window_realization_keys[winid] or {}
    for key in pairs(retired) do
      bs.window_placement_keys[winid][key] = nil
      bs.window_realization_keys[winid][key] = nil
    end
    for _, item in ipairs(tracks) do
      local key, track = item.key, item.track
      local projection = bs.projections[key]
      local descriptor = descriptor_for(projection, track, adapter, ctx, window_ctx, image.config)
      descriptor.meta = descriptor.meta or {}
      descriptor.meta.ref = vim.deepcopy(projection.ref)
      desired[key][descriptor.key] = true
      bs.window_placement_keys[winid][key] = true
      bs.window_realization_keys[winid][key] = descriptor.key
      transaction.upsert[key] = request_for_demand(bs, projection, track, adapter, descriptor, image.config)
        or source_request(track, "unavailable")
      if geometry[key] then
        transaction.refresh[key] = true
      end
      queue_descriptor(bs, batches, adapter_name, projection, descriptor, item.priority)
    end
  end

  for key, desired_keys in pairs(desired) do
    bs.projections[key].desired_keys = desired_keys
  end
  session.prune_full(bufnr, wanted_realizations(bs))
  for _, winid in ipairs(wins) do
    placement.reconcile_window(winid, transactions[winid])
  end
  for key in pairs(affected) do
    evict_inactive_realizations(bs, bs.projections[key])
  end

  dispatch_batches(bufnr, binding, adapter, batches, ctx, image.config)
end

local function place_ready_realization(bufnr, bs, projection, track, adapter, asset, config)
  for _, winid in ipairs(active_windows(bufnr)) do
    local placement_keys = bs.window_placement_keys[winid]
    local realization_keys = bs.window_realization_keys[winid]
    if
      placement_keys ~= nil
      and placement_keys[projection.key] == true
      and realization_keys ~= nil
      and realization_keys[projection.key] == asset.key
    then
      local request = adapter.placement_request(asset, track, config)
      if request ~= nil then
        placement.reconcile_window(winid, {
          upsert = { [projection.key] = request },
          conceal_in_normal = config.conceal_in_normal == true,
          visibility_scope = "realization",
        })
      end
    end
  end
end

local syncing = {}

local function sync_demands(bufnr)
  if syncing[bufnr] then
    return
  end
  syncing[bufnr] = true
  local ok, err = xpcall(function()
    local image = require("math-conceal.image")
    local binding = image.get_binding(bufnr)
    if binding == nil or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local adapter_name, adapter = adapter_for(binding)
    local bs = state.get_buf_state(bufnr)
    bs.window_placement_keys = bs.window_placement_keys or {}
    bs.window_realization_keys = bs.window_realization_keys or {}
    bs.placement_windows = bs.placement_windows or {}
    local ctx = context.resolve(bufnr, binding, tracker.get_context(bufnr), image.config)
    bs.context = ctx
    local tracks_by_key = track_view.by_key(bufnr, { require_valid = true })
    prune_projection_table(bs, tracks_by_key)
    local wins = active_windows(bufnr)
    local tracks = ordered_tracks(tracks_by_key, wins)
    for _, item in ipairs(tracks) do
      ensure_projection(bs, bufnr, item.track)
    end

    local desired_by_win = {}
    local wanted_realizations = {}
    local batches = {}
    for _, winid in ipairs(wins) do
      local window_ctx = realization_common.window_context(winid, image.config)
      desired_by_win[winid] = {}
      for _, item in ipairs(tracks) do
        local key, track = item.key, item.track
        local projection = bs.projections[key]
        local descriptor = descriptor_for(projection, track, adapter, ctx, window_ctx, image.config)
        descriptor.meta = descriptor.meta or {}
        descriptor.meta.ref = vim.deepcopy(projection.ref)
        desired_by_win[winid][key] = { descriptor = descriptor }
        projection.desired_keys[descriptor.key] = true
        wanted_realizations[descriptor.key] = true
        queue_descriptor(bs, batches, adapter_name, projection, descriptor, item.priority)
      end
    end

    for _, projection in pairs(bs.projections) do
      local current_desired = {}
      for _, demands in pairs(desired_by_win) do
        local demand = demands[projection.key]
        if demand ~= nil then
          current_desired[demand.descriptor.key] = true
        end
      end
      projection.desired_keys = current_desired
    end
    session.prune_full(bufnr, wanted_realizations)
    place_windows(bufnr, wins, bs, tracks_by_key, adapter, desired_by_win, image.config)
    for _, projection in pairs(bs.projections) do
      evict_inactive_realizations(bs, projection)
    end

    dispatch_batches(bufnr, binding, adapter, batches, ctx, image.config, function()
      vim.schedule(function()
        sync_demands(bufnr)
      end)
    end)
  end, debug.traceback)
  syncing[bufnr] = nil
  if not ok then
    error(err, 0)
  end
end

function M.on_tracker_repair(event)
  if event.initial == true or event.force == true then
    sync_demands(event.bufnr)
  else
    sync_repair(event)
  end
  require("math-conceal.image.preview").schedule(event.bufnr, { immediate = true })
end

function M.handle_service_response(bufnr, resp, meta)
  if meta ~= nil and meta.kind == "live_preview" then
    require("math-conceal.image.preview").handle_service_response(bufnr, resp, meta)
    return
  end
  if type(resp) ~= "table" or meta == nil or meta.kind ~= "realization" then
    return
  end

  local descriptor = meta.node_meta and meta.node_meta[resp.node_id] or nil
  local descriptor_meta = descriptor and descriptor.meta or nil
  local bs = state.get_buf_state(bufnr)
  local projection = descriptor_meta and bs.projections[descriptor_meta.projection_key] or nil
  local pending = projection and projection.pending[descriptor.key] or nil
  if
    projection == nil
    or pending == nil
    or pending.token ~= descriptor.pending_token
    or projection.desired_keys[descriptor.key] ~= true
  then
    return
  end

  local track = track_view.for_projection(projection, { require_valid = true })
  if
    track == nil
    or tonumber(track.rev or -1) ~= tonumber(descriptor_meta.track_rev or -2)
    or tostring(resp.context_id or "") ~= tostring(descriptor_meta.context_id or "")
    or tonumber(resp.context_rev or -1) ~= tonumber(descriptor_meta.context_rev or -2)
    or tonumber(resp.node_rev or -1) ~= tonumber(descriptor_meta.track_rev or -2)
  then
    projection.pending[descriptor.key] = nil
    return
  end

  local adapter = realization_registry.require(meta.adapter)
  local accepted = adapter.accept_response(resp, descriptor)
  if accepted == nil then
    return
  end
  projection.pending[descriptor.key] = nil
  update_diagnostics(bufnr, resp.node_id, descriptor, accepted)
  if accepted.status ~= "ready" then
    projection.failed[descriptor.key] = true
    projection.status = "failed"
    return
  end

  local cols, rows = grid.natural_dimensions(
    accepted.display_kind,
    accepted.source_rows or descriptor.source_rows,
    accepted.width_px,
    accepted.height_px
  )
  local asset = {
    key = descriptor.key,
    realization_key = descriptor.key,
    layout_key = descriptor.layout_key,
    image_id = state.allocate_image_id(bufnr),
    path = accepted.path,
    width_px = accepted.width_px,
    height_px = accepted.height_px,
    natural_grid = { cols = cols, rows = rows },
    cols = cols,
    rows = rows,
    display_kind = accepted.display_kind,
    placement_style = accepted.placement_style or {},
    render_key = descriptor.key,
  }
  if not terminal.send_image(asset.path, asset.image_id) then
    terminal.delete_image(asset.image_id)
    projection.failed[descriptor.key] = true
    projection.status = "failed"
    return
  end

  local previous = projection.realizations[descriptor.key]
  if previous ~= nil then
    release_asset(previous)
  end
  projection.realizations[descriptor.key] = asset
  projection.failed[descriptor.key] = nil
  projection.status = "ready"
  touch_asset(bs, projection, asset)
  place_ready_realization(bufnr, bs, projection, track, adapter, asset, require("math-conceal.image").config)
end

function M.sync_cursor(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  local wins = active_windows(bufnr)
  if bs.placement_window_key ~= window_set_key(wins) then
    sync_demands(bufnr)
  else
    for _, winid in ipairs(wins) do
      placement.reconcile_window(winid, {
        conceal_in_normal = require("math-conceal.image").config.conceal_in_normal == true,
      })
    end
  end
  require("math-conceal.image.preview").schedule(bufnr, { immediate = opts.preview_immediate == true })
end

function M.refresh(bufnr)
  bufnr = normalize_bufnr(bufnr)
  sync_demands(bufnr)
  require("math-conceal.image.preview").refresh(bufnr)
end

function M.on_layout_change(bufnr)
  sync_demands(normalize_bufnr(bufnr))
  require("math-conceal.image.preview").refresh(normalize_bufnr(bufnr))
end

function M.close_window(winid)
  placement.close_window(winid)
  for _, bs in pairs(state.buffers) do
    if bs.placement_windows ~= nil then
      bs.placement_windows[winid] = nil
    end
    if bs.window_placement_keys ~= nil then
      bs.window_placement_keys[winid] = nil
    end
    if bs.window_realization_keys ~= nil then
      bs.window_realization_keys[winid] = nil
    end
    bs.placement_window_key = nil
  end
end

function M.close_tab(tabpage)
  if tabpage == nil or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    M.close_window(winid)
  end
end

function M.repair_source_reveal_refs(bufnr, refs)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  for _, ref in ipairs(refs or {}) do
    local projection = bs.projections[tracker.track_ref_key(ref)]
    if projection ~= nil then
      projection.failed = vim.tbl_extend("force", projection.failed or {}, projection.desired_keys or {})
    end
  end
  sync_demands(bufnr)
end

function M.force_render(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  for _, projection in pairs(bs.projections or {}) do
    close_projection_assets(projection)
  end
  sync_demands(bufnr)
end

function M.current_track_for_projection(projection, opts)
  return track_view.for_projection(projection, opts)
end

function M.current_tracks_by_key(bufnr, opts)
  return track_view.by_key(bufnr, opts)
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  require("math-conceal.image.preview").detach(bufnr)
  placement.close_buffer(bufnr)
  for _, projection in pairs(bs.projections or {}) do
    cleanup_projection(projection)
  end
  session.stop(bufnr)
  state.drop_buf(bufnr)
end

function M._sync_demands(bufnr)
  sync_demands(normalize_bufnr(bufnr))
end

return M
