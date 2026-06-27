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

local function code_flow_service_cache_key(ctx, config, layout_sig)
  return table.concat({
    "typst-code-flow",
    ctx and ctx.context_id or "",
    tostring(ctx and ctx.context_rev or 0),
    wrapper.render_size_key(config),
    vim.fn.sha256(layout_sig or ""),
  }, ":")
end

local function ref_from_track(track)
  return {
    bufnr = track.bufnr,
    tracker_generation = track.tracker_generation,
    generation = track.generation,
    track_id = track.track_id,
    id = track.track_id,
  }
end

local function code_flow_pending_key(signature, inline_key, block_key)
  return vim.fn.sha256(table.concat({
    "code-flow",
    signature or "",
    inline_key or "",
    block_key or "",
  }, "\0"))
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

local function make_code_variant(track, ctx, config, role, opts)
  local display_track = flow_classification.apply_role(track, role, opts)
  if display_track == nil then
    return nil
  end

  local source, line_map = wrapper.build_slot_document(display_track, ctx, config)
  return {
    track = display_track,
    source = source,
    source_hash = vim.fn.sha256(source),
    render_key = render_key(display_track, ctx, config),
    line_map = line_map,
    source_display_kind = display_track.source_display_kind,
    source_rows = display_track.source_rows,
    render_whole_line = display_track.render_whole_line == true,
  }
end

local function make_code_flow_node(projection, track, ctx, config, layout_sig)
  local signature = flow_classification.signature(track, ctx, layout_sig)
  local flow_source, flow_target = wrapper.build_flow_source(track, ctx)
  local inline = make_code_variant(track, ctx, config, "inline", {
    flow_role = "inline",
    render_policy = "inline_naturalized",
  })
  local block = make_code_variant(track, ctx, config, "block", {
    flow_role = "inline",
    render_policy = "block_constrained",
  })
  if inline == nil or block == nil then
    return nil
  end

  local pending_key = code_flow_pending_key(signature, inline.render_key, block.render_key)
  return {
    node = {
      node_id = projection.key,
      node_rev = track.rev or 0,
      source_hash = track.source_hash,
      kind = track.object_kind or track.node_type or "code",
      flow_source = flow_source,
      target_start = flow_target and flow_target.target_start or nil,
      target_end = flow_target and flow_target.target_end or nil,
      variants = {
        inline = {
          source = inline.source,
          source_hash = inline.source_hash,
        },
        block = {
          source = block.source,
          source_hash = block.source_hash,
        },
      },
    },
    meta = {
      projection_key = projection.key,
      pending_key = pending_key,
      ref = ref_from_track(track),
      signature = signature,
      track_rev = track.rev or 0,
      context_id = ctx.context_id,
      context_rev = ctx.context_rev,
      variants = {
        inline = inline,
        block = block,
      },
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

local function source_reveal_projection(projection, binding, config)
  projection.pending_key = nil
  projection.status = "source_reveal"
  cleanup_asset(projection.visible_asset)
  projection.visible_asset = nil
  if uses_formula_display(binding) then
    set_display_asset(projection, nil, true)
    formula_display.repair_tracks(projection.bufnr, { projection.ref }, config)
  else
    display.reveal(projection)
  end
end

local function render_code_flow_affected(bufnr, binding, ctx, config, render_items)
  local nodes = {}
  local node_meta = {}
  local ready_refs = {}
  local layout_sig, metrics = flow_classification.layout_signature(bufnr, config)

  for _, item in ipairs(render_items) do
    local projection = item.projection
    local track = item.track
    local already_ready = false
    local entry = flow_classification.classification(bufnr, track, ctx)
    if entry ~= nil and entry.layout_role ~= "inline" and entry.layout_role ~= "block" then
      source_reveal_projection(projection, binding, config)
      already_ready = true
    end
    local classified = renderable_track(bufnr, track, ctx)
    if classified ~= nil then
      local key = render_key(classified, ctx, config)
      if projection.visible_asset and projection.visible_asset.render_key == key then
        projection.pending_key = nil
        projection.status = "visible"
        if uses_formula_display(binding) then
          set_display_asset(projection, projection.visible_asset, false)
          ready_refs[#ready_refs + 1] = projection.ref
        end
        already_ready = true
      end
    end

    if not already_ready then
      local built = make_code_flow_node(projection, track, ctx, config, layout_sig)
      if built ~= nil and projection.pending_key ~= built.meta.pending_key then
        nodes[#nodes + 1] = built.node
        node_meta[built.node.node_id] = built.meta
        projection.pending_key = built.meta.pending_key
        projection.status = "code_flow_pending"
        set_display_asset(projection, nil, true)
      end
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
    type = "render_code_flow",
    request_id = req_id,
    cache_key = code_flow_service_cache_key(ctx, config, layout_sig),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.context_source,
    flow_context_source = ctx.flow_context_source or ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    output_dir = ctx.workspace.outputs_dir,
    ppi = state.render_ppi(config),
    worker_count = config.formula_worker_count or 2,
    layout_width_pt = metrics.width_pt,
    layout_baseline_pt = metrics.baseline_pt,
    nodes = nodes,
  }

  local ok = session.render_code_flow(bufnr, binding, payload, {
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

local function handle_code_flow_response(bufnr, resp, meta)
  if type(resp) ~= "table" or resp.type ~= "code_flow_rendered" or meta == nil then
    return
  end

  local image = require("math-conceal.image")
  local binding = image.get_binding(bufnr)
  if binding == nil then
    return
  end
  local bs = state.get_buf_state(bufnr)
  local node_meta = meta.node_meta and meta.node_meta[resp.node_id] or nil
  local projection = node_meta and bs.projections[node_meta.projection_key] or nil
  if projection == nil then
    return
  end

  local track = track_view.for_projection(projection)
  if track == nil or (track.object_kind or track.node_type) ~= "code" then
    return
  end

  local ctx = context.resolve(bufnr, binding, tracker.get_context(bufnr), image.config)
  local layout_sig = flow_classification.layout_signature(bufnr, image.config)
  local current_signature = flow_classification.signature(track, ctx, layout_sig)
  if
    projection.pending_key ~= node_meta.pending_key
    or current_signature ~= node_meta.signature
    or tostring(resp.context_id or "") ~= tostring(node_meta.context_id or "")
    or tonumber(resp.context_rev or -1) ~= tonumber(node_meta.context_rev or -2)
    or tonumber(resp.node_rev or -1) ~= tonumber(node_meta.track_rev or -2)
    or tonumber(track.rev or -1) ~= tonumber(node_meta.track_rev or -2)
  then
    return
  end

  projection.pending_key = nil
  local flow_ok = flow_classification.store_response(bufnr, projection.key, node_meta.signature, track, resp)
  if not flow_ok then
    update_diagnostics(bufnr, { node_id = resp.node_id, diagnostics = {} }, node_meta)
    source_reveal_projection(projection, binding, image.config)
    return
  end

  local selected = resp.selected_variant
  local variant_meta = selected and node_meta.variants and node_meta.variants[selected] or nil
  if
    variant_meta == nil
    or (resp.selected_variant_hash ~= nil and resp.selected_variant_hash ~= variant_meta.source_hash)
  then
    update_diagnostics(bufnr, { node_id = resp.node_id, diagnostics = resp.render_diagnostics or {} }, variant_meta)
    source_reveal_projection(projection, binding, image.config)
    return
  end

  update_diagnostics(bufnr, { node_id = resp.node_id, diagnostics = resp.render_diagnostics or {} }, variant_meta)
  if resp.render_status ~= "ok" or type(resp.path) ~= "string" or resp.path == "" then
    projection.status = "failed"
    cleanup_asset(projection.visible_asset)
    projection.visible_asset = nil
    if uses_formula_display(binding) then
      set_display_asset(projection, nil, true)
      repair_formula_display(bufnr, { projection.ref })
    else
      display.reveal(projection)
    end
    return
  end

  local display_track = flow_classification.apply_role(track, resp.layout_role or resp.flow_role, {
    flow_role = resp.flow_role,
    render_policy = resp.render_policy,
    reason = resp.layout_reason,
  })
  if display_track == nil then
    source_reveal_projection(projection, binding, image.config)
    return
  end

  local cols, rows = display.cell_dimensions(display_track, resp.width_px, resp.height_px, image.config)
  local candidate = {
    image_id = state.allocate_image_id(bufnr),
    path = resp.path,
    width_px = resp.width_px,
    height_px = resp.height_px,
    cols = cols,
    rows = rows,
    render_key = variant_meta.render_key,
  }

  local uploaded
  if uses_formula_display(binding) then
    uploaded = terminal.send_image(candidate.path, candidate.image_id)
  else
    uploaded = terminal.upload(candidate.path, candidate.image_id, candidate.cols, candidate.rows)
  end
  if not uploaded then
    projection.status = "failed"
    cleanup_asset(projection.visible_asset)
    projection.visible_asset = nil
    if uses_formula_display(binding) then
      set_display_asset(projection, nil, true)
      repair_formula_display(bufnr, { projection.ref })
    else
      display.reveal(projection)
    end
    return
  end
  candidate.uploaded = true

  local old = projection.visible_asset
  projection.visible_asset = candidate
  projection.status = "visible"

  if uses_formula_display(binding) then
    set_display_asset(projection, candidate, false)
    formula_display.repair_tracks(bufnr, { projection.ref }, image.config)
  elseif cursor_reveals(bufnr, track, image.config) then
    display.reveal(projection)
  else
    display.show(projection, display_track, candidate, image.config)
  end

  cleanup_asset(old)
end

local function refresh_asset_cell_geometry(projection, track, config)
  local asset = projection and projection.visible_asset or nil
  if asset == nil or asset.width_px == nil or asset.height_px == nil then
    return false
  end
  if track == nil or track.source_display_kind ~= "block" then
    return false
  end

  local cols, rows = display.cell_dimensions(track, asset.width_px, asset.height_px, config)
  if asset.cols == cols and asset.rows == rows then
    return false
  end

  asset.cols = cols
  asset.rows = rows
  set_display_asset(projection, asset, false)
  return true
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
  local to_code_render = {}
  for key, track in pairs(by_key) do
    local projection = ensure_projection(bs, bufnr, track)

    if track.invalid then
      cleanup_projection(projection)
    elseif render_keys[key] then
      if (track.object_kind or track.node_type) == "code" then
        to_code_render[#to_code_render + 1] = { projection = projection, track = track }
      else
        to_render[#to_render + 1] = { projection = projection, track = track }
      end
    end
  end

  render_affected(bufnr, binding, ctx, image.config, to_render)
  render_code_flow_affected(bufnr, binding, ctx, image.config, to_code_render)
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
  if meta ~= nil and meta.kind == "code_flow_render" then
    handle_code_flow_response(bufnr, resp, meta)
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

  local binding = image.get_binding(bufnr)
  local uploaded
  if uses_formula_display(binding) then
    uploaded = terminal.send_image(candidate.path, candidate.image_id)
  else
    uploaded = terminal.upload(candidate.path, candidate.image_id, candidate.cols, candidate.rows)
  end
  if not uploaded then
    cleanup_asset(projection.visible_asset)
    projection.visible_asset = nil
    projection.status = "failed"
    if uses_formula_display(binding) then
      set_display_asset(projection, nil, true)
      repair_formula_display(bufnr, { projection.ref })
    else
      display.reveal(projection)
    end
    return
  end
  candidate.uploaded = true

  local old = projection.visible_asset
  projection.visible_asset = candidate
  projection.status = "visible"

  if uses_formula_display(binding) then
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
  local to_code_render = {}
  for _, projection in pairs(bs.projections or {}) do
    local track = track_view.for_projection(projection, { require_valid = true })
    if track == nil then
      cleanup_projection(projection)
    elseif (track.object_kind or track.node_type) == "code" then
      to_code_render[#to_code_render + 1] = { projection = projection, track = track }
    else
      refresh_asset_cell_geometry(projection, track, image.config)
    end
  end

  render_affected(bufnr, binding, ctx, image.config, to_render)
  render_code_flow_affected(bufnr, binding, ctx, image.config, to_code_render)
  formula_display.refresh(bufnr, image.config)
  require("math-conceal.image.preview").refresh(bufnr)
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
