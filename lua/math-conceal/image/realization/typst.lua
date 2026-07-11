local common = require("math-conceal.image.realization.common")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

local function is_code(track)
  return (track.object_kind or track.node_type) == "code"
end

local function code_style(ctx, display_kind)
  if display_kind ~= "block" then
    return {}
  end
  local cfg = ctx.code_block or {}
  return {
    horizontal_align = "source",
    fit = {
      left_padding_cols = math.max(0, tonumber(cfg.padding_cols) or 0),
      right_padding_cols = math.max(0, tonumber(cfg.right_padding_cols) or 1),
    },
  }
end

local function math_style(display_kind)
  return display_kind == "block" and { horizontal_align = "center" } or {}
end

local function apply_code_role(track, role, render_policy)
  local copy = vim.deepcopy(track)
  copy.source_display_kind = role
  copy.render_whole_line = role == "block"
  copy.source_rows = role == "inline" and 1
    or (track.source_rows or math.max(1, (track.end_row or 0) - (track.row or 0) + 1))
  copy.source_facts = vim.deepcopy(copy.source_facts or {})
  copy.source_facts.flow_role = "inline"
  copy.source_facts.layout_role = role
  copy.source_facts.render_policy = render_policy
  return copy
end

local function code_variant(track, ctx, config, layout, role, policy)
  local display_track = apply_code_role(track, role, policy)
  local source, line_map = wrapper.build_slot_document(display_track, ctx, config, layout.window)
  return {
    source = source,
    source_hash = vim.fn.sha256(source),
    line_map = line_map,
    display_kind = role,
    placement_style = code_style(ctx, role),
  }
end

function M.layout(track, window_context, _ctx, _config)
  if not is_code(track) then
    return common.shared_layout()
  end
  return {
    key = "window:" .. window_context.signature,
    signature = window_context.signature,
    window = window_context,
  }
end

local function describe_formula(track, ctx, layout, config, projection_key)
  local key = common.realization_key(track, ctx, config, layout.key, "typst-math")
  local source, line_map = wrapper.build_slot_document(track, ctx, config)
  local display_kind = track.source_display_kind or "inline"
  return {
    adapter = "typst",
    batch_kind = "formula",
    key = key,
    layout_key = layout.key,
    pending_visibility = "previous",
    display_kind = display_kind,
    placement_style = math_style(display_kind),
    node = {
      node_id = projection_key,
      node_rev = track.rev or 0,
      source_hash = vim.fn.sha256(source),
      kind = track.object_kind or track.node_type or "math",
      source = source,
    },
    meta = {
      projection_key = projection_key,
      realization_key = key,
      track_rev = track.rev or 0,
      context_id = ctx.context_id,
      context_rev = ctx.context_rev,
      line_map = line_map,
    },
  }
end

local function describe_code(track, ctx, layout, config, projection_key)
  local key = common.realization_key(track, ctx, config, layout.key, "typst-code-flow")
  local flow_source, target = wrapper.build_flow_source(track, ctx)
  local inline = code_variant(track, ctx, config, layout, "inline", "inline_naturalized")
  local block = code_variant(track, ctx, config, layout, "block", "block_constrained")
  local signature = vim.fn.sha256(table.concat({
    key,
    ctx.flow_context_source or ctx.context_source or "",
    ctx.effective_root or "",
    common.context_inputs_signature(ctx),
  }, "\0"))
  return {
    adapter = "typst",
    batch_kind = "code_flow",
    key = key,
    layout_key = layout.key,
    pending_visibility = "source",
    layout = layout,
    node = {
      node_id = projection_key,
      node_rev = track.rev or 0,
      source_hash = track.source_hash,
      kind = track.object_kind or track.node_type or "code",
      flow_source = flow_source,
      target_start = target and target.target_start or nil,
      target_end = target and target.target_end or nil,
      variants = {
        inline = { source = inline.source, source_hash = inline.source_hash },
        block = { source = block.source, source_hash = block.source_hash },
      },
    },
    meta = {
      projection_key = projection_key,
      realization_key = key,
      signature = signature,
      track_rev = track.rev or 0,
      context_id = ctx.context_id,
      context_rev = ctx.context_rev,
      variants = { inline = inline, block = block },
    },
  }
end

function M.describe(track, ctx, layout, config, projection_key)
  if is_code(track) then
    return describe_code(track, ctx, layout, config, projection_key)
  end
  return describe_formula(track, ctx, layout, config, projection_key)
end

local function dispatch_formula(bufnr, binding, batch)
  local nodes, node_meta = {}, {}
  for _, descriptor in ipairs(batch.descriptors or {}) do
    nodes[#nodes + 1] = descriptor.node
    node_meta[descriptor.node.node_id] = descriptor
  end
  local ctx, config = batch.context, batch.config
  return session.render_formulas(bufnr, binding, {
    type = "render_formulas",
    backend = ctx.backend or "typst",
    request_id = batch.request_id,
    cache_key = table.concat({
      "typst",
      ctx.context_id or "",
      tostring(ctx.context_rev or 0),
      wrapper.render_size_key(config),
    }, ":"),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    output_dir = ctx.workspace.outputs_dir,
    ppi = state.render_ppi(config),
    worker_count = config.formula_worker_count or 2,
    nodes = nodes,
  }, {
    kind = "realization",
    adapter = "typst",
    request_id = batch.request_id,
    node_meta = node_meta,
    expected = #nodes,
  })
end

local function dispatch_code(bufnr, binding, batch)
  local nodes, node_meta = {}, {}
  for _, descriptor in ipairs(batch.descriptors or {}) do
    nodes[#nodes + 1] = descriptor.node
    node_meta[descriptor.node.node_id] = descriptor
  end
  local ctx, config = batch.context, batch.config
  local window = batch.layout.window
  return session.render_code_flow(bufnr, binding, {
    type = "render_code_flow",
    request_id = batch.request_id,
    cache_key = table.concat({
      "typst-code-flow",
      ctx.context_id or "",
      tostring(ctx.context_rev or 0),
      wrapper.render_size_key(config),
      batch.layout.signature,
    }, ":"),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.context_source,
    flow_context_source = ctx.flow_context_source or ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    output_dir = ctx.workspace.outputs_dir,
    ppi = state.render_ppi(config),
    worker_count = config.formula_worker_count or 2,
    layout_width_pt = window.width_pt,
    layout_baseline_pt = window.baseline_pt,
    nodes = nodes,
  }, {
    kind = "realization",
    adapter = "typst",
    request_id = batch.request_id,
    node_meta = node_meta,
    expected = #nodes,
  })
end

function M.dispatch_batch(bufnr, binding, batch)
  if batch.kind == "code_flow" then
    return dispatch_code(bufnr, binding, batch)
  end
  return dispatch_formula(bufnr, binding, batch)
end

function M.accept_response(resp, descriptor)
  if descriptor.batch_kind == "formula" then
    if type(resp) ~= "table" or resp.type ~= "formula_rendered" then
      return nil
    end
    return {
      status = resp.status == "ok" and type(resp.path) == "string" and resp.path ~= "" and "ready" or "failed",
      path = resp.path,
      width_px = resp.width_px,
      height_px = resp.height_px,
      display_kind = descriptor.display_kind,
      placement_style = descriptor.placement_style,
      diagnostics = resp.diagnostics or {},
    }
  end

  if type(resp) ~= "table" or resp.type ~= "code_flow_rendered" then
    return nil
  end
  local selected = resp.selected_variant
  local variant = selected and descriptor.meta.variants[selected] or nil
  local valid = resp.flow_status == "ok"
    and (resp.layout_role == "inline" or resp.layout_role == "block")
    and variant ~= nil
    and (resp.selected_variant_hash == nil or resp.selected_variant_hash == variant.source_hash)
  return {
    status = valid and resp.render_status == "ok" and type(resp.path) == "string" and resp.path ~= "" and "ready"
      or "failed",
    path = resp.path,
    width_px = resp.width_px,
    height_px = resp.height_px,
    display_kind = valid and resp.layout_role or nil,
    placement_style = valid and variant.placement_style or nil,
    line_map = variant and variant.line_map or nil,
    diagnostics = resp.render_diagnostics or {},
    flow_diagnostics = resp.flow_diagnostics or {},
    flow_status = resp.flow_status,
    flow_role = resp.flow_role,
    layout_role = resp.layout_role,
  }
end

function M.placement_request(realization, view, _config)
  return common.placement_request(realization, view)
end

return M
