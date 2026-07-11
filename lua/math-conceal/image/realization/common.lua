local boundary = require("math-conceal.image.realization.boundary")
local state = require("math-conceal.image.state")
local tracker = require("math-conceal.image.tracker")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

local function baseline_pt(config)
  local baseline = tonumber(config and config.math_baseline_pt) or 11
  return baseline > 0 and baseline or 11
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

function M.context_inputs_signature(ctx)
  return table.concat(stable_table_parts((ctx and ctx.inputs) or {}), "\0")
end

function M.window_context(winid, config)
  local info = vim.fn.getwininfo(winid)[1] or {}
  local text_width = math.max(1, vim.api.nvim_win_get_width(winid) - (tonumber(info.textoff) or 0))
  local baseline = baseline_pt(config)
  local cell_w, cell_h = state.cell_size()
  local cell_w_pt = cell_w ~= nil and cell_h ~= nil and baseline * (cell_w / cell_h) or baseline * 0.55
  local signature = table.concat({
    tostring(baseline),
    tostring(text_width),
    tostring(cell_w or ""),
    tostring(cell_h or ""),
    tostring(cell_w_pt),
  }, "\0")
  return {
    winid = winid,
    text_width = text_width,
    baseline_pt = baseline,
    cell_w = cell_w,
    cell_h = cell_h,
    cell_w_pt = cell_w_pt,
    width_pt = text_width * cell_w_pt,
    signature = vim.fn.sha256(signature),
  }
end

function M.shared_layout()
  return { key = "shared", signature = "shared" }
end

function M.realization_key(track, ctx, config, layout_key, variant)
  return vim.fn.sha256(table.concat({
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
    layout_key or "shared",
    variant or "",
  }, "\0"))
end

function M.ref(track)
  return {
    bufnr = track.bufnr,
    tracker_generation = track.tracker_generation,
    generation = track.generation,
    track_id = track.track_id,
    id = track.track_id,
  }
end

function M.placement_request(realization, view)
  if realization == nil or view == nil then
    return nil
  end
  local role = boundary.role(view, realization.display_kind)
  if role == "sandwich" then
    return { state = "source", ref = M.ref(view), reason = "sandwich" }
  end
  return {
    state = "ready",
    ref = M.ref(view),
    realization_key = realization.key,
    image_id = realization.image_id,
    natural_grid = vim.deepcopy(realization.natural_grid),
    display_kind = realization.display_kind,
    source_boundary_role = role,
    placement_style = vim.deepcopy(realization.placement_style or {}),
  }
end

return M
