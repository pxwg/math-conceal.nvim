--- Adapter-level render viewport and coverage resolution.
---
--- Source adapters may export `render_policy(bufnr, opts)` and return:
---   { kind = "buffer" }
---   { kind = "progressive", margin = 0, step = 120, delay_ms = 80 }
---
--- For compatibility, adapters may still export `render_viewport(bufnr, opts)` and return:
---   { kind = "buffer" }
---   { kind = "visible", margin = 0 }
---   { kind = "visible", ranges = { { top = 0, bottom = 20 } } }
---
--- Missing adapters and missing viewport hooks default to whole-buffer.  A
--- progressive policy scans the buffer but expands render coverage outward
--- from the current viewport across repeated render passes.

local M = {}

local DEFAULT_PROGRESSIVE_STEP = 120
local DEFAULT_PROGRESSIVE_DELAY_MS = 80

local function source_kind_for_bufnr(bufnr)
  local ok, main = pcall(require, "math-conceal.image")
  if ok and type(main.source_kind_for_bufnr) == "function" then
    return main.source_kind_for_bufnr(bufnr)
  end

  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr) or ""
  if ft == "typst" or name:match("%.typ$") then
    return "typst"
  elseif ft == "markdown" or name:match("%.md$") or name:match("%.markdown$") then
    return "markdown"
  elseif ft == "tex" or ft == "plaintex" or ft == "latex" or name:match("%.tex$") then
    return "latex"
  end
  return nil
end

local function adapter_for_source(source_kind)
  if type(source_kind) ~= "string" or source_kind == "" then
    return nil
  end
  local ok, adapter = pcall(require, "math-conceal.image.source-adapters." .. source_kind)
  if ok and type(adapter) == "table" then
    return adapter
  end
  return nil
end

local function clamp_row(row, line_count)
  row = tonumber(row) or 0
  if line_count <= 0 then
    return 0
  end
  return math.max(0, math.min(math.floor(row), line_count - 1))
end

local function normalize_ranges(ranges, line_count)
  local normalized = {}
  for _, range in ipairs(ranges or {}) do
    local top = range.top or range[1] or range.start_row
    local bottom = range.bottom or range[2] or range.end_row or top
    top = clamp_row(top, line_count)
    bottom = clamp_row(bottom, line_count)
    if bottom < top then
      top, bottom = bottom, top
    end
    normalized[#normalized + 1] = {
      top = top,
      bottom = bottom,
    }
  end

  table.sort(normalized, function(a, b)
    if a.top ~= b.top then
      return a.top < b.top
    end
    return a.bottom < b.bottom
  end)

  local merged = {}
  for _, range in ipairs(normalized) do
    local prev = merged[#merged]
    if prev ~= nil and range.top <= prev.bottom + 1 then
      prev.bottom = math.max(prev.bottom, range.bottom)
    else
      merged[#merged + 1] = range
    end
  end
  return merged
end

local function copy_ranges(ranges)
  local out = {}
  for _, range in ipairs(ranges or {}) do
    out[#out + 1] = {
      top = range.top,
      bottom = range.bottom,
    }
  end
  return out
end

local function ranges_cover_buffer(ranges, line_count)
  if line_count <= 0 then
    return true
  end
  return #ranges == 1 and ranges[1].top <= 0 and ranges[1].bottom >= line_count - 1
end

local function merge_range_sets(a, b, line_count)
  local ranges = {}
  for _, range in ipairs(a or {}) do
    ranges[#ranges + 1] = range
  end
  for _, range in ipairs(b or {}) do
    ranges[#ranges + 1] = range
  end
  return normalize_ranges(ranges, line_count)
end

function M.buffer()
  return {
    kind = "buffer",
  }
end

local function normalize_policy(policy)
  if type(policy) ~= "table" then
    return {
      kind = "buffer",
    }
  end

  if policy.kind == "progressive" or policy.kind == "visible" then
    return {
      kind = "progressive",
      margin = math.max(0, math.floor(tonumber(policy.margin or policy.initial_margin) or 0)),
      step = math.max(1, math.floor(tonumber(policy.step or policy.step_margin) or DEFAULT_PROGRESSIVE_STEP)),
      delay_ms = math.max(0, math.floor(tonumber(policy.delay_ms) or DEFAULT_PROGRESSIVE_DELAY_MS)),
    }
  end

  return {
    kind = "buffer",
  }
end

local function policy_from_viewport(viewport)
  if type(viewport) == "table" and viewport.kind == "visible" then
    return normalize_policy({
      kind = "progressive",
      margin = viewport.margin or 0,
    })
  end
  return normalize_policy({
    kind = "buffer",
  })
end

function M.resolve_policy(bufnr, opts)
  opts = opts or {}
  local source_kind = opts.source_kind or source_kind_for_bufnr(bufnr)
  local adapter = adapter_for_source(source_kind)

  local policy_fn = adapter and adapter.render_policy or nil
  if type(policy_fn) == "function" then
    local ok, policy = pcall(policy_fn, bufnr, opts)
    if ok then
      return normalize_policy(policy)
    end
    return normalize_policy(nil)
  end

  local viewport_fn = adapter and adapter.render_viewport or nil
  if type(viewport_fn) == "function" then
    local ok, viewport = pcall(viewport_fn, bufnr, opts)
    if ok then
      return policy_from_viewport(viewport)
    end
  end

  return normalize_policy(nil)
end

function M.visible(bufnr, opts)
  opts = opts or {}
  local margin = math.max(0, math.floor(tonumber(opts.margin) or 0))
  local line_count = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_line_count(bufnr) or 0
  local ranges = {}

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      local ok, range = pcall(vim.api.nvim_win_call, winid, function()
        return {
          top = vim.fn.line("w0") - 1 - margin,
          bottom = vim.fn.line("w$") - 1 + margin,
        }
      end)
      if ok and range ~= nil then
        ranges[#ranges + 1] = range
      end
    end
  end

  return {
    kind = "visible",
    margin = margin,
    ranges = normalize_ranges(ranges, line_count),
  }
end

function M.resolve(bufnr, opts)
  local policy = M.resolve_policy(bufnr, opts)
  if policy.kind ~= "progressive" then
    return M.buffer()
  end
  return M.visible(bufnr, { margin = policy.margin or 0 })
end

function M.current_viewport(bufnr, opts)
  local policy = M.resolve_policy(bufnr, opts)
  if policy.kind ~= "progressive" then
    return M.buffer()
  end
  return M.visible(bufnr, { margin = 0 })
end

function M.key(viewport)
  viewport = viewport or M.buffer()
  if viewport.kind ~= "visible" then
    return "buffer"
  end

  local parts = { "visible", tostring(viewport.margin or 0) }
  for _, range in ipairs(viewport.ranges or {}) do
    parts[#parts + 1] = tostring(range.top) .. ":" .. tostring(range.bottom)
  end
  return table.concat(parts, "|")
end

function M.is_buffer(viewport)
  return viewport == nil or viewport.kind == nil or viewport.kind == "buffer"
end

function M.range_overlaps(viewport, range)
  if M.is_buffer(viewport) then
    return true
  end
  if range == nil then
    return false
  end
  for _, rows in ipairs(viewport.ranges or {}) do
    if range[3] >= rows.top and range[1] <= rows.bottom then
      return true
    end
  end
  return false
end

function M.distance_to_viewport(viewport, range)
  if M.is_buffer(viewport) then
    return 0
  end
  if range == nil then
    return math.huge
  end

  local best = math.huge
  for _, rows in ipairs(viewport.ranges or {}) do
    if range[3] >= rows.top and range[1] <= rows.bottom then
      return 0
    end
    if range[3] < rows.top then
      best = math.min(best, rows.top - range[3])
    elseif range[1] > rows.bottom then
      best = math.min(best, range[1] - rows.bottom)
    end
  end
  return best
end

function M.resolve_render_plan(bufnr, opts)
  opts = opts or {}
  local policy = M.resolve_policy(bufnr, opts)
  if policy.kind ~= "progressive" then
    return {
      policy = policy,
      render_viewport = M.buffer(),
      render_viewport_key = "buffer",
      render_coverage = M.buffer(),
      render_coverage_key = "buffer",
      render_coverage_state = {
        complete = true,
      },
      render_coverage_complete = true,
      render_coverage_can_grow = false,
      render_coverage_delay_ms = 0,
    }
  end

  local line_count = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_line_count(bufnr) or 0
  local priority_viewport = M.visible(bufnr, { margin = 0 })
  local viewport_key = M.key(priority_viewport)
  local brs = require("math-conceal.image.state").buffer_render_state[bufnr] or {}
  local prev_state = brs.render_coverage_state or {}
  local prev_ranges = copy_ranges(prev_state.ranges or (brs.render_coverage and brs.render_coverage.ranges) or {})

  local has_anchor = #((priority_viewport and priority_viewport.ranges) or {}) > 0
  local same_anchor = has_anchor and prev_state.anchor_key == viewport_key
  local next_margin = policy.margin
  if same_anchor and prev_state.complete ~= true then
    next_margin = (prev_state.margin or policy.margin) + policy.step
  end

  local expanded = has_anchor and M.visible(bufnr, { margin = next_margin }) or { kind = "visible", ranges = {} }
  local ranges = merge_range_sets(prev_ranges, expanded.ranges, line_count)
  local complete = ranges_cover_buffer(ranges, line_count)
  local coverage = complete and M.buffer() or {
    kind = "visible",
    margin = next_margin,
    ranges = ranges,
  }

  return {
    policy = policy,
    render_viewport = priority_viewport,
    render_viewport_key = viewport_key,
    render_coverage = coverage,
    render_coverage_key = M.key(coverage),
    render_coverage_state = {
      anchor_key = viewport_key,
      margin = next_margin,
      ranges = ranges,
      complete = complete,
    },
    render_coverage_complete = complete,
    render_coverage_can_grow = has_anchor and not complete,
    render_coverage_delay_ms = policy.delay_ms,
  }
end

function M.changed_since_last_render(bufnr)
  local policy = M.resolve_policy(bufnr)
  if policy.kind ~= "progressive" then
    return false, M.buffer(), "buffer"
  end

  local viewport = M.current_viewport(bufnr)
  local key = M.key(viewport)
  local brs = require("math-conceal.image.state").buffer_render_state[bufnr]
  return brs == nil or brs.render_viewport_key ~= key or brs.render_coverage_complete ~= true, viewport, key
end

return M
