local common = require("math-conceal.image.realization.common")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

function M.layout(_track, _window_context, _ctx, _config)
  return common.shared_layout()
end

function M.describe(track, ctx, layout, config, projection_key)
  local key = common.realization_key(track, ctx, config, layout.key, "markdown-math")
  local source, line_map = wrapper.build_slot_document(track, ctx, config)
  local display_kind = track.source_display_kind or "inline"
  return {
    adapter = "markdown",
    batch_kind = "formula",
    key = key,
    layout_key = layout.key,
    pending_visibility = "previous",
    display_kind = display_kind,
    placement_style = display_kind == "block" and { horizontal_align = "center" } or {},
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

function M.dispatch_batch(bufnr, binding, batch)
  local descriptors = batch.descriptors or {}
  local nodes, node_meta = {}, {}
  for _, descriptor in ipairs(descriptors) do
    nodes[#nodes + 1] = descriptor.node
    node_meta[descriptor.node.node_id] = descriptor
  end
  local ctx, config = batch.context, batch.config
  local payload = {
    type = "render_formulas",
    backend = ctx.backend or "typst",
    request_id = batch.request_id,
    cache_key = table.concat({
      "markdown",
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
  }
  return session.render_formulas(bufnr, binding, payload, {
    kind = "realization",
    adapter = "markdown",
    request_id = batch.request_id,
    node_meta = node_meta,
    expected = #nodes,
  })
end

function M.accept_response(resp, descriptor)
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

function M.placement_request(realization, view, _config)
  return common.placement_request(realization, view)
end

return M
