local context = require("math-conceal.image.context")
local display = require("math-conceal.image.display")
local flow_classification = require("math-conceal.image.flow-classification")
local formula_display = require("math-conceal.image.formula-display")
local quickfix = require("math-conceal.image.quickfix")
local repair_event = require("math-conceal.image.repair-event")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")
local tracker = require("math-conceal.image.tracker")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function render_key(track, ctx, config)
  local parts = {
    tracker.track_ref_key(track),
    tostring(track.rev or 0),
    track.source_hash or "",
    track.prelude_signature or "",
    ctx.context_id or "",
    tostring(ctx.context_rev or 0),
    tostring(state.render_ppi(config)),
    wrapper.render_size_key(config),
    tostring(track.source_display_kind or ""),
    tostring(track.render_whole_line == true),
  }
  local layout_key = wrapper.render_layout_key(track, ctx, config)
  if layout_key ~= "" then
    parts[#parts + 1] = layout_key
  end
  return vim.fn.sha256(table.concat(parts, "\0"))
end

local function ensure_projection(bs, bufnr, track)
  local key = tracker.track_ref_key(track)
  local projection = bs.projections[key]
  if projection == nil then
    projection = {
      bufnr = bufnr,
      key = key,
      ref = {
        bufnr = bufnr,
        tracker_generation = track.tracker_generation,
        track_id = track.track_id,
      },
    }
    bs.projections[key] = projection
  end
  projection.ref.track_id = track.track_id
  projection.ref.tracker_generation = track.tracker_generation
  return projection, key
end

local function uses_formula_display(binding)
  return binding ~= nil and (binding.kind == "typst" or binding.source_kind == "typst" or binding.scanner == "typst")
end

local function in_range(row, col, range)
  if row < range.row or row > range.end_row then
    return false
  end
  if range.row == range.end_row then
    return col >= range.col and col <= range.end_col
  end
  return (row == range.row and col >= range.col)
    or (row == range.end_row and col <= range.end_col)
    or (row > range.row and row < range.end_row)
end

local function cursor_reveals(bufnr, track, config)
  if track == nil then
    return false
  end
  if config.conceal_in_normal == true and vim.api.nvim_get_mode().mode == "n" then
    return false
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return in_range(cursor[1] - 1, cursor[2], track)
end

local function cleanup_asset(asset)
  if asset ~= nil and asset.image_id ~= nil then
    terminal.delete(asset.image_id)
  end
end

local function set_display_asset(projection, asset, source_reveal)
  local bs = state.get_buf_state(projection.bufnr)
  bs.display_assets = bs.display_assets or {}
  bs.display_assets[projection.key] = {
    asset = asset,
    source_reveal = source_reveal == true,
  }
end

local function clear_display_asset(projection)
  local bs = state.get_buf_state(projection.bufnr)
  if bs.display_assets ~= nil then
    bs.display_assets[projection.key] = nil
  end
end

local function repair_formula_display(bufnr, refs)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if uses_formula_display(binding) then
    formula_display.repair_tracks(bufnr, refs, image.config)
  end
end

local function cleanup_projection(projection)
  display.clear(projection)
  clear_display_asset(projection)
  cleanup_asset(projection.visible_asset)
  cleanup_asset(projection.candidate_asset)
  projection.visible_asset = nil
  projection.candidate_asset = nil
  projection.status = "retired"
end

local function rebuild_quickfix(bufnr)
  quickfix.rebuild(bufnr)
end

local function map_generated_pos(line_map, line, col)
  if line_map == nil then
    return nil
  end
  if line < line_map.gen_start or line > line_map.gen_end then
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

local function update_diagnostics(bufnr, resp, node_meta)
  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  local bucket = state.render_diagnostics[bufnr]
  bucket.formula_by_node = bucket.formula_by_node or {}

  local node_id = resp.node_id
  if type(resp.diagnostics) ~= "table" or #resp.diagnostics == 0 then
    bucket.formula_by_node[node_id] = nil
    rebuild_quickfix(bufnr)
    return
  end

  local items = {}
  for _, diag in ipairs(resp.diagnostics) do
    local line = tonumber(diag.line) or 1
    local col = tonumber(diag.column) or 1
    local filename = diag.file
    local mapped = map_generated_pos(node_meta and node_meta.line_map, line, col)
    if mapped ~= nil and (filename == nil or tostring(filename):find("/__typst_concealer__/", 1, true) ~= nil) then
      filename = mapped.filename
      line = mapped.lnum
      col = mapped.col
    elseif filename == nil or filename == "" then
      filename = vim.api.nvim_buf_get_name(bufnr)
    end

    items[#items + 1] = {
      filename = filename,
      lnum = line,
      col = col,
      text = "[service/formula] " .. (diag.message or "render error"),
      type = diag.severity == "warning" and "W" or "E",
      _formula_node_id = node_id,
    }
  end

  bucket.formula_by_node[node_id] = items
  rebuild_quickfix(bufnr)
end

local function request_id(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.next_request_id = (bs.next_request_id or 0) + 1
  return ("image:%d:%d"):format(bufnr, bs.next_request_id)
end

local function service_cache_key(ctx, config)
  return table.concat({
    "typst",
    ctx and ctx.context_id or "",
    tostring(ctx and ctx.context_rev or 0),
    wrapper.render_size_key(config),
  }, ":")
end

local function make_node(projection, track, ctx, config)
  local source, line_map = wrapper.build_slot_document(track, ctx, config)
  local key = render_key(track, ctx, config)
  return {
    node = {
      node_id = projection.key,
      node_rev = track.rev or 0,
      source_hash = vim.fn.sha256(source),
      kind = track.object_kind or track.node_type or "math",
      source = source,
    },
    meta = {
      projection_key = projection.key,
      render_key = key,
      track_rev = track.rev or 0,
      prelude_signature = track.prelude_signature,
      context_id = ctx.context_id,
      context_rev = ctx.context_rev,
      line_map = line_map,
      object_kind = track.object_kind or track.node_type or "math",
      source_display_kind = track.source_display_kind,
      source_rows = track.source_rows,
      render_whole_line = track.render_whole_line == true,
    },
  }
end

local function renderable_track(bufnr, track, ctx)
  if (track.object_kind or track.node_type) ~= "code" then
    return track
  end
  local entry = flow_classification.classification(bufnr, track, ctx)
  if entry == nil then
    return nil
  end
  return flow_classification.apply_role(track, entry.layout_role or entry.flow_role, {
    flow_role = entry.flow_role,
    render_policy = entry.render_policy,
    reason = entry.layout_reason,
  })
end

local function render_affected(bufnr, binding, ctx, config, render_items)
  local nodes = {}
  local node_meta = {}
  local ready_refs = {}
  for _, item in ipairs(render_items) do
    local projection = item.projection
    local track = item.track
    local key = render_key(track, ctx, config)
    if projection.visible_asset and projection.visible_asset.render_key == key then
      projection.pending_key = nil
      projection.status = "visible"
      if uses_formula_display(binding) then
        set_display_asset(projection, projection.visible_asset, false)
        ready_refs[#ready_refs + 1] = projection.ref
      end
    elseif projection.pending_key ~= key then
      local built = make_node(projection, track, ctx, config)
      nodes[#nodes + 1] = built.node
      node_meta[built.node.node_id] = built.meta
      projection.pending_key = key
      projection.status = "pending"
    end
  end

  if #ready_refs > 0 then
    formula_display.repair_tracks(bufnr, ready_refs, config)
  end

  if #nodes == 0 then
    return
  end

  local req_id = request_id(bufnr)
  local payload = {
    type = "render_formulas",
    backend = ctx.backend or "typst",
    request_id = req_id,
    cache_key = service_cache_key(ctx, config),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    output_dir = ctx.workspace.outputs_dir,
    ppi = state.render_ppi(config),
    worker_count = config.formula_worker_count or 2,
    nodes = nodes,
  }

  local ok = session.render_formulas(bufnr, binding, payload, {
    request_id = req_id,
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    node_meta = node_meta,
    expected = #nodes,
  })

  if not ok then
    local failed_refs = {}
    for _, item in ipairs(render_items) do
      local projection = item.projection
      projection.pending_key = nil
      projection.status = "failed"
      if uses_formula_display(binding) then
        set_display_asset(projection, nil, true)
        failed_refs[#failed_refs + 1] = projection.ref
      else
        display.reveal(projection)
      end
    end
    if #failed_refs > 0 then
      formula_display.repair_tracks(bufnr, failed_refs, config)
    end
  end
end

local function render_trigger_keys(event)
  if event.initial == true or event.force == true then
    return repair_event.current_track_key_set(event)
  end

  local keys = repair_event.ref_set(event.identity_changed_refs)
  repair_event.merge_keys(keys, repair_event.ref_set(event.born_refs))
  repair_event.merge_keys(keys, repair_event.context_dependent_key_set(event))
  return keys
end

function M.on_tracker_repair(event)
  local image = require("math-conceal.image")
  local bufnr = event.bufnr
  local binding = image.get_binding(bufnr)
  if binding == nil then
    return
  end

  local bs = state.get_buf_state(bufnr)
  local ctx = context.resolve(bufnr, binding, event.context, image.config)
  local by_key = repair_event.tracks_by_key(event)
  local render_keys = render_trigger_keys(event)

  for _, ref in ipairs(event.retired_refs or {}) do
    local key = tracker.track_ref_key(ref)
    local projection = bs.projections[key]
    if projection ~= nil then
      cleanup_projection(projection)
      bs.projections[key] = nil
    end
  end
  flow_classification.clear_refs(bufnr, event.retired_refs or {})

  local to_render = {}
  local to_classify = {}
  for key, track in pairs(by_key) do
    local projection = ensure_projection(bs, bufnr, track)

    if track.invalid then
      cleanup_projection(projection)
    elseif render_keys[key] then
      if (track.object_kind or track.node_type) == "code" then
        local classified = renderable_track(bufnr, track, ctx)
        if classified ~= nil then
          to_render[#to_render + 1] = { projection = projection, track = classified }
        else
          projection.pending_key = nil
          projection.status = "flow_pending"
          set_display_asset(projection, nil, true)
          to_classify[#to_classify + 1] = track
        end
      else
        to_render[#to_render + 1] = { projection = projection, track = track }
      end
    end
  end

  if #to_classify > 0 then
    flow_classification.request(bufnr, binding, ctx, to_classify)
  end
  render_affected(bufnr, binding, ctx, image.config, to_render)
  if uses_formula_display(binding) then
    formula_display.on_tracker_repair(event, image.config)
    require("math-conceal.image.preview").schedule(bufnr, { immediate = true })
    return
  end
  M.sync_cursor(bufnr)
end

function M.handle_service_response(bufnr, resp, meta)
  if meta ~= nil and meta.kind == "live_preview" then
    require("math-conceal.image.preview").handle_service_response(bufnr, resp, meta)
    return
  end
  if meta ~= nil and meta.kind == "flow_classification" then
    flow_classification.handle_service_response(bufnr, resp, meta)
    return
  end

  if type(resp) ~= "table" or resp.type ~= "formula_rendered" then
    return
  end
  local bs = state.get_buf_state(bufnr)
  local node_meta = meta and meta.node_meta and meta.node_meta[resp.node_id] or nil
  local projection = node_meta and bs.projections[node_meta.projection_key] or nil
  if projection == nil then
    return
  end

  local track = track_view.for_projection(projection)
  if track == nil then
    return
  end
  local display_track = track
  if node_meta.object_kind == "code" then
    display_track = vim.deepcopy(track)
    display_track.source_display_kind = node_meta.source_display_kind
    display_track.source_rows = node_meta.source_rows
    display_track.render_whole_line = node_meta.render_whole_line == true
  end

  if
    projection.pending_key ~= node_meta.render_key
    or tostring(resp.context_id or "") ~= tostring(node_meta.context_id or "")
    or tonumber(resp.context_rev or -1) ~= tonumber(node_meta.context_rev or -2)
    or tonumber(resp.node_rev or -1) ~= tonumber(node_meta.track_rev or -2)
    or tonumber(track.rev or -1) ~= tonumber(node_meta.track_rev or -2)
  then
    return
  end

  update_diagnostics(bufnr, resp, node_meta)
  projection.pending_key = nil
  if resp.status ~= "ok" or type(resp.path) ~= "string" or resp.path == "" then
    cleanup_asset(projection.visible_asset)
    projection.visible_asset = nil
    projection.status = "failed"
    local image = require("math-conceal.image")
    if uses_formula_display(image.get_binding(bufnr)) then
      set_display_asset(projection, nil, true)
      repair_formula_display(bufnr, { projection.ref })
    else
      display.reveal(projection)
    end
    return
  end

  local image = require("math-conceal.image")
  local cols, rows = display.cell_dimensions(display_track, resp.width_px, resp.height_px, image.config)
  local candidate = {
    image_id = state.allocate_image_id(bufnr),
    path = resp.path,
    width_px = resp.width_px,
    height_px = resp.height_px,
    cols = cols,
    rows = rows,
    render_key = node_meta.render_key,
  }

  if not terminal.upload(candidate.path, candidate.image_id, candidate.cols, candidate.rows) then
    cleanup_asset(projection.visible_asset)
    projection.visible_asset = nil
    projection.status = "failed"
    if uses_formula_display(image.get_binding(bufnr)) then
      set_display_asset(projection, nil, true)
      repair_formula_display(bufnr, { projection.ref })
    else
      display.reveal(projection)
    end
    return
  end

  local old = projection.visible_asset
  projection.visible_asset = candidate
  projection.status = "visible"

  if uses_formula_display(image.get_binding(bufnr)) then
    set_display_asset(projection, candidate, false)
    formula_display.repair_tracks(bufnr, { projection.ref }, image.config)
  elseif cursor_reveals(bufnr, track, image.config) then
    display.reveal(projection)
  else
    display.show(projection, display_track, candidate, image.config)
  end

  cleanup_asset(old)
end

function M.sync_cursor(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if uses_formula_display(binding) then
    formula_display.sync_cursor(bufnr, image.config)
    require("math-conceal.image.preview").schedule(bufnr, { immediate = opts.preview_immediate == true })
    return
  end

  local bs = state.get_buf_state(bufnr)
  local tracks_by_key = track_view.by_key(bufnr)
  for _, projection in pairs(bs.projections or {}) do
    if projection.visible_asset ~= nil and projection.status ~= "failed" then
      local track = track_view.for_projection(projection, { by_key = tracks_by_key })
      if track == nil then
        cleanup_projection(projection)
      elseif cursor_reveals(bufnr, track, image.config) then
        display.reveal(projection)
      elseif projection.revealed then
        display.show(projection, track, projection.visible_asset, image.config)
      end
    end
  end
  require("math-conceal.image.preview").schedule(bufnr, { immediate = opts.preview_immediate == true })
end

function M.refresh(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if uses_formula_display(binding) then
    formula_display.refresh(bufnr, image.config)
    require("math-conceal.image.preview").refresh(bufnr)
    return
  end

  local bs = state.get_buf_state(bufnr)
  for _, projection in pairs(bs.projections or {}) do
    if projection.visible_asset ~= nil and not projection.revealed then
      local track = track_view.for_projection(projection)
      if track == nil then
        cleanup_projection(projection)
      else
        display.show(projection, track, projection.visible_asset, image.config)
      end
    end
  end
  require("math-conceal.image.preview").refresh(bufnr)
end

function M.on_layout_change(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil then
    return
  end
  if not uses_formula_display(binding) then
    M.refresh(bufnr)
    return
  end

  local ctx = context.resolve(bufnr, binding, tracker.get_context(bufnr), image.config)
  local bs = state.get_buf_state(bufnr)
  local to_render = {}
  local to_classify = {}
  for _, projection in pairs(bs.projections or {}) do
    local track = track_view.for_projection(projection, { require_valid = true })
    if track == nil then
      cleanup_projection(projection)
    elseif (track.object_kind or track.node_type) == "code" then
      local classified = renderable_track(bufnr, track, ctx)
      if classified ~= nil then
        local key = render_key(classified, ctx, image.config)
        if projection.visible_asset == nil or projection.visible_asset.render_key ~= key then
          set_display_asset(projection, nil, true)
        end
        to_render[#to_render + 1] = { projection = projection, track = classified }
      else
        projection.pending_key = nil
        projection.status = "flow_pending"
        set_display_asset(projection, nil, true)
        to_classify[#to_classify + 1] = track
      end
    end
  end

  if #to_classify > 0 then
    flow_classification.request(bufnr, binding, ctx, to_classify)
  end
  render_affected(bufnr, binding, ctx, image.config, to_render)
  formula_display.refresh(bufnr, image.config)
  require("math-conceal.image.preview").refresh(bufnr)
end

function M.render_refs_after_flow(bufnr, refs)
  bufnr = normalize_bufnr(bufnr)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil then
    return
  end

  local ctx = context.resolve(bufnr, binding, tracker.get_context(bufnr), image.config)
  local bs = state.get_buf_state(bufnr)
  local to_render = {}
  for _, ref in ipairs(refs or {}) do
    local key = tracker.track_ref_key(ref)
    local projection = bs.projections[key]
    local track = tracker.resolve_ref(ref)
    local classified = renderable_track(bufnr, track, ctx)
    if projection ~= nil and classified ~= nil then
      to_render[#to_render + 1] = { projection = projection, track = classified }
    end
  end
  render_affected(bufnr, binding, ctx, image.config, to_render)
end

function M.repair_source_reveal_refs(bufnr, refs)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  local repair_refs = {}
  for _, ref in ipairs(refs or {}) do
    local key = tracker.track_ref_key(ref)
    local projection = bs.projections[key]
    if projection ~= nil then
      projection.pending_key = nil
      projection.status = "source_reveal"
      cleanup_asset(projection.visible_asset)
      projection.visible_asset = nil
      set_display_asset(projection, nil, true)
      repair_refs[#repair_refs + 1] = projection.ref
    end
  end
  if #repair_refs > 0 then
    local image = require("math-conceal.image")
    if uses_formula_display(image.get_binding(bufnr)) then
      formula_display.repair_tracks(bufnr, repair_refs, image.config)
    end
  end
end

function M.force_render(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil then
    return
  end
  local tracks = tracker.get_tracks(bufnr)
  local event = {
    bufnr = bufnr,
    generation = tracks[1] and tracks[1].generation or nil,
    tracker_generation = tracks[1] and tracks[1].tracker_generation or nil,
    force = true,
    tracks = tracks,
    retired_refs = {},
    context = tracker.get_context(bufnr),
  }
  M.on_tracker_repair(event)
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
  formula_display.detach(bufnr)
  for _, projection in pairs(bs.projections or {}) do
    cleanup_projection(projection)
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.display_ns, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.aux_ns, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.preview_ns, 0, -1)
  end
  session.stop(bufnr)
  state.drop_buf(bufnr)
end

return M
