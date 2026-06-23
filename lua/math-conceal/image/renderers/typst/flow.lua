local quickfix = require("math-conceal.image.quickfix")
local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")
local tracker = require("math-conceal.image.tracker")
local wrapper = require("math-conceal.image.renderers.typst.wrapper")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function flow_state(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.flow_classification = bs.flow_classification or {
    roles = {},
    requested = {},
  }
  return bs.flow_classification
end

local function stable_table_parts(value, out, prefix)
  out = out or {}
  prefix = prefix or ""
  if type(value) ~= "table" then
    out[#out + 1] = prefix .. tostring(value or "")
    return out
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for _, key in ipairs(keys) do
    stable_table_parts(value[key], out, prefix .. tostring(key) .. "=")
  end
  return out
end

local function context_inputs_signature(ctx)
  return table.concat(stable_table_parts((ctx and ctx.inputs) or {}), "\0")
end

local function baseline_pt(config)
  local baseline = tonumber(config and config.math_baseline_pt) or 11
  if baseline <= 0 then
    baseline = 11
  end
  return baseline
end

local function service_cache_key(ctx)
  return "typst:" .. (ctx and ctx.context_id or "") .. ":" .. tostring(ctx and ctx.context_rev or 0)
end

local function is_code_track(track)
  return track ~= nil and (track.object_kind or track.node_type) == "code"
end

local function layout_metrics(bufnr, config)
  local baseline = baseline_pt(config)
  local win_cols = state.visible_text_width(bufnr)
  local cell_w, cell_h = state.cell_size()
  local cell_w_pt
  if cell_w ~= nil and cell_h ~= nil then
    cell_w_pt = baseline * (cell_w / cell_h)
  else
    cell_w_pt = baseline * 0.55
  end
  return {
    baseline_pt = baseline,
    win_cols = win_cols,
    cell_w = cell_w,
    cell_h = cell_h,
    cell_w_pt = cell_w_pt,
    width_pt = math.max(1, win_cols) * cell_w_pt,
  }
end

local function layout_signature(bufnr, config)
  local metrics = layout_metrics(bufnr, config)
  return table.concat({
    tostring(metrics.baseline_pt),
    tostring(metrics.win_cols),
    tostring(metrics.cell_w or ""),
    tostring(metrics.cell_h or ""),
    tostring(metrics.cell_w_pt),
    tostring(metrics.width_pt),
  }, "\0"),
    metrics
end

function M.signature(track, ctx, layout_sig)
  return vim.fn.sha256(table.concat({
    tostring(track.rev or 0),
    track.source_hash or "",
    track.prelude_signature or "",
    ctx and ctx.context_id or "",
    tostring(ctx and ctx.context_rev or 0),
    ctx and (ctx.flow_context_source or ctx.context_source) or "",
    ctx and ctx.effective_root or "",
    context_inputs_signature(ctx),
    layout_sig or "",
  }, "\0"))
end

function M.classification(bufnr, track, ctx)
  if not is_code_track(track) then
    return nil
  end
  bufnr = normalize_bufnr(bufnr or track.bufnr)
  local key = tracker.track_ref_key(track)
  local layout_sig = layout_signature(bufnr, require("math-conceal.image").config)
  local signature = M.signature(track, ctx, layout_sig)
  local entry = flow_state(bufnr).roles[key]
  if entry ~= nil and entry.signature == signature then
    return entry
  end
  return nil
end

function M.flow_role(bufnr, track, ctx)
  local entry = M.classification(bufnr, track, ctx)
  return entry and (entry.flow_role or "unknown") or nil
end

function M.layout_role(bufnr, track, ctx)
  local entry = M.classification(bufnr, track, ctx)
  return entry and (entry.layout_role or entry.flow_role or "unknown") or nil
end

local function render_policy_for_roles(flow_role, layout_role)
  if layout_role == "inline" then
    return "inline_naturalized"
  end
  if layout_role == "block" then
    if flow_role == "inline" then
      return "block_constrained"
    end
    return "block"
  end
  return nil
end

function M.apply_role(track, role, opts)
  if not is_code_track(track) or (role ~= "inline" and role ~= "block") then
    return nil
  end
  opts = opts or {}
  local flow_role = opts.flow_role or role
  local source_rows = track.source_rows or math.max(1, (track.end_row or track.row or 0) - (track.row or 0) + 1)

  local copy = vim.deepcopy(track)
  copy.source_display_kind = role
  copy.render_whole_line = role == "block"
  if role == "inline" then
    copy.source_rows = 1
  else
    copy.source_rows = source_rows
  end
  copy.source_facts = vim.deepcopy(copy.source_facts or {})
  copy.source_facts.break_line = copy.row ~= copy.end_row
  copy.source_facts.flow_role = flow_role
  copy.source_facts.layout_role = role
  copy.source_facts.render_policy = opts.render_policy or render_policy_for_roles(flow_role, role)
  if opts.reason ~= nil and opts.reason ~= "" then
    copy.source_facts.display_role_reason = opts.reason
  elseif flow_role ~= role then
    copy.source_facts.display_role_reason = "layout_probe"
  end
  return copy
end

local function request_id(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.next_flow_request_id = (bs.next_flow_request_id or 0) + 1
  return ("flow:%d:%d"):format(bufnr, bs.next_flow_request_id)
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

local function clear_report(bufnr, key)
  quickfix.set_items(bufnr, "flow_by_node", key, nil)
end

local function report_unknown(bufnr, key, track, resp)
  local message = "failed to classify Typst code flow/layout; showing source"
  if type(resp) == "table" and type(resp.diagnostics) == "table" and resp.diagnostics[1] ~= nil then
    message = message .. ": " .. tostring(resp.diagnostics[1].message or "unknown error")
  elseif type(resp) == "table" and resp.layout_role == "unknown" then
    message = "Typst code layout is unknown; showing source"
  elseif type(resp) == "table" and resp.flow_role == "unknown" then
    message = "Typst code flow is unknown; showing source"
  end

  quickfix.set_items(bufnr, "flow_by_node", key, {
    {
      filename = vim.api.nvim_buf_get_name(bufnr),
      lnum = (track.row or 0) + 1,
      col = (track.col or 0) + 1,
      text = "[service/flow] " .. message,
      type = "W",
      _flow_node_id = key,
    },
  })
end

function M.clear_refs(bufnr, refs)
  bufnr = normalize_bufnr(bufnr)
  local fs = flow_state(bufnr)
  for _, ref in ipairs(refs or {}) do
    local key = tracker.track_ref_key(ref)
    fs.roles[key] = nil
    fs.requested[key] = nil
    clear_report(bufnr, key)
  end
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  bs.flow_classification = nil
  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  state.render_diagnostics[bufnr].flow_by_node = nil
  quickfix.rebuild(bufnr)
end

function M.request(bufnr, binding, ctx, tracks)
  bufnr = normalize_bufnr(bufnr)
  if binding == nil or ctx == nil then
    return {}
  end

  local fs = flow_state(bufnr)
  local nodes = {}
  local node_meta = {}
  local requested_refs = {}
  local layout_sig, metrics = layout_signature(bufnr, require("math-conceal.image").config)

  for _, track in ipairs(tracks or {}) do
    if is_code_track(track) and track.invalid ~= true and track.state == "valid" then
      local key = tracker.track_ref_key(track)
      local signature = M.signature(track, ctx, layout_sig)
      local role = fs.roles[key]
      if (role == nil or role.signature ~= signature) and fs.requested[key] ~= signature then
        fs.requested[key] = signature
        local flow_source, flow_target = wrapper.build_flow_source(track, ctx)
        nodes[#nodes + 1] = {
          node_id = key,
          node_rev = track.rev or 0,
          source_hash = track.source_hash,
          kind = track.object_kind or track.node_type or "code",
          source = flow_source,
          target_start = flow_target and flow_target.target_start or nil,
          target_end = flow_target and flow_target.target_end or nil,
        }
        node_meta[key] = {
          key = key,
          ref = ref_from_track(track),
          signature = signature,
          track_rev = track.rev or 0,
          context_id = ctx.context_id,
          context_rev = ctx.context_rev,
        }
        requested_refs[#requested_refs + 1] = ref_from_track(track)
      end
    end
  end

  if #nodes == 0 then
    return requested_refs
  end

  local req_id = request_id(bufnr)
  local payload = {
    type = "classify_flow",
    request_id = req_id,
    cache_key = service_cache_key(ctx),
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    context_source = ctx.flow_context_source or ctx.context_source,
    root = ctx.effective_root,
    inputs = ctx.inputs or vim.empty_dict(),
    layout_width_pt = metrics.width_pt,
    layout_baseline_pt = metrics.baseline_pt,
    nodes = nodes,
  }

  local ok = session.classify_flow(bufnr, binding, payload, {
    request_id = req_id,
    context_id = ctx.context_id,
    context_rev = ctx.context_rev,
    node_meta = node_meta,
    expected = #nodes,
  })

  if not ok then
    for _, node in ipairs(nodes) do
      fs.requested[node.node_id] = nil
    end
  end

  return requested_refs
end

function M.handle_service_response(bufnr, resp, meta)
  if type(resp) ~= "table" or resp.type ~= "flow_classified" or meta == nil then
    return
  end

  bufnr = normalize_bufnr(bufnr)
  local fs = flow_state(bufnr)
  local node_meta = meta.node_meta and meta.node_meta[resp.node_id] or nil
  if node_meta == nil then
    return
  end

  if fs.requested[resp.node_id] == node_meta.signature then
    fs.requested[resp.node_id] = nil
  end
  local track = tracker.resolve_ref(node_meta.ref)
  local ctx = state.get_buf_state(bufnr).context
  local layout_sig = layout_signature(bufnr, require("math-conceal.image").config)
  if track == nil or not is_code_track(track) or M.signature(track, ctx, layout_sig) ~= node_meta.signature then
    return
  end

  local role = resp.flow_role or "unknown"
  local layout_role = resp.layout_role or role
  fs.roles[resp.node_id] = {
    signature = node_meta.signature,
    flow_role = role,
    layout_role = layout_role,
    render_policy = render_policy_for_roles(role, layout_role),
    layout_break = resp.layout_break == true,
    layout_reason = resp.layout_reason,
  }

  if resp.status == "ok" and (layout_role == "inline" or layout_role == "block") then
    clear_report(bufnr, resp.node_id)
    require("math-conceal.image.projection").render_refs_after_flow(bufnr, { node_meta.ref })
    return
  end

  report_unknown(bufnr, resp.node_id, track, resp)
  require("math-conceal.image.projection").repair_source_reveal_refs(bufnr, { node_meta.ref })
end

return M
