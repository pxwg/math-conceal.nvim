local quickfix = require("math-conceal.image.quickfix")
local state = require("math-conceal.image.state")
local tracker = require("math-conceal.image.tracker")

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

M.layout_signature = layout_signature

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

M.render_policy_for_roles = render_policy_for_roles

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

local function clear_report(bufnr, key)
  quickfix.set_items(bufnr, "flow_by_node", key, nil)
end

local function report_unknown(bufnr, key, track, resp)
  local message = "failed to classify Typst code flow/layout; showing source"
  local diagnostics = type(resp) == "table" and (resp.flow_diagnostics or resp.diagnostics) or nil
  if type(diagnostics) == "table" and diagnostics[1] ~= nil then
    message = message .. ": " .. tostring(diagnostics[1].message or "unknown error")
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

function M.store_response(bufnr, key, signature, track, resp)
  bufnr = normalize_bufnr(bufnr)
  local role = type(resp) == "table" and (resp.flow_role or "unknown") or "unknown"
  local layout_role = type(resp) == "table" and (resp.layout_role or role) or role
  local ok = type(resp) == "table"
    and resp.flow_status == "ok"
    and role ~= "unknown"
    and (layout_role == "inline" or layout_role == "block")

  flow_state(bufnr).roles[key] = {
    signature = signature,
    flow_role = role,
    layout_role = layout_role,
    render_policy = resp and resp.render_policy or render_policy_for_roles(role, layout_role),
    layout_break = resp and resp.layout_break == true,
    layout_reason = resp and resp.layout_reason,
  }

  if ok then
    clear_report(bufnr, key)
  else
    report_unknown(bufnr, key, track, resp)
  end
  return ok
end

function M.clear_refs(bufnr, refs)
  bufnr = normalize_bufnr(bufnr)
  local fs = flow_state(bufnr)
  for _, ref in ipairs(refs or {}) do
    local key = tracker.track_ref_key(ref)
    fs.roles[key] = nil
    clear_report(bufnr, key)
  end
end

return M
