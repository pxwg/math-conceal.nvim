--- LaTeX math source adapter.
--- Collects top-level LaTeX math nodes and emits planner-compatible entries.

local M = {}

local latex_query = nil

local function get_query()
  if latex_query == nil then
    latex_query = vim.treesitter.query.parse(
      "latex",
      [[
[
 (inline_formula)
 (displayed_equation)
 (math_environment)
] @math
]]
    )
  end
  return latex_query
end

local function range_to_string(bufnr, range)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #lines == 0 then
    return ""
  end
  if start_row == end_row then
    lines[1] = (lines[1] or ""):sub(start_col + 1, end_col)
  else
    lines[1] = (lines[1] or ""):sub(start_col + 1)
    lines[#lines] = (lines[#lines] or ""):sub(1, end_col)
  end
  return table.concat(lines, "\n")
end

local function hash_string(value)
  local ok, digest = pcall(vim.fn.sha256, value or "")
  if ok and type(digest) == "string" and digest ~= "" then
    return digest:sub(1, 16)
  end

  local h = 0
  value = value or ""
  for i = 1, #value do
    h = (h * 31 + value:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

local function range_overlaps_rows(range, start_row, end_row)
  return range[3] >= start_row and range[1] <= end_row
end

local function build_match_index(bufnr, root, query, start_row, end_row)
  local index = {}
  for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row, { all = true }) do
    local node = match[1] and match[1][1]
    if node ~= nil then
      local node_type = node:type()
      if node_type == "inline_formula" or node_type == "displayed_equation" or node_type == "math_environment" then
        index[node:id()] = {
          node = node,
          backend_node_type = node_type,
          node_type = "math",
          range = { node:range() },
        }
      end
    end
  end
  return index
end

local function collect_top_level_units(root, match_index, start_row, end_row)
  local units = {}

  local function visit(node)
    if node == nil then
      return
    end

    local sr, _, er, _ = node:range()
    if start_row ~= nil and end_row ~= nil and (er < start_row or sr > end_row) then
      return
    end

    local entry = match_index[node:id()]
    if entry ~= nil then
      if start_row == nil or range_overlaps_rows(entry.range, start_row, end_row) then
        units[#units + 1] = entry
      end
      return
    end

    for child in node:iter_children() do
      if child:named() then
        visit(child)
      end
    end
  end

  visit(root)
  return units
end

local function units_overlap_rows(unit, start_row, end_row)
  return range_overlaps_rows(unit.range, start_row, end_row)
end

local function expand_rows_to_cover_units(units, start_row, end_row)
  local expanded_start = start_row
  local expanded_end = end_row
  local changed = true
  while changed do
    changed = false
    for _, unit in ipairs(units or {}) do
      if units_overlap_rows(unit, expanded_start, expanded_end) then
        if unit.range[1] < expanded_start then
          expanded_start = unit.range[1]
          changed = true
        end
        if unit.range[3] > expanded_end then
          expanded_end = unit.range[3]
          changed = true
        end
      end
    end
  end
  return expanded_start, expanded_end
end

local function merge_units_in_rows(prev_units, new_units, start_row, end_row)
  local merged = {}
  local inserted = false
  for _, unit in ipairs(prev_units or {}) do
    if unit.range[3] < start_row then
      merged[#merged + 1] = unit
    elseif unit.range[1] > end_row then
      if not inserted then
        for _, new_unit in ipairs(new_units or {}) do
          merged[#merged + 1] = new_unit
        end
        inserted = true
      end
      merged[#merged + 1] = unit
    end
  end
  if not inserted then
    for _, new_unit in ipairs(new_units or {}) do
      merged[#merged + 1] = new_unit
    end
  end
  return merged
end

local function begin_document_row(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:find("\\begin%s*{%s*document%s*}") then
      return idx - 1
    end
  end
  return nil
end

local function pending_touches_preamble(bufnr, pending)
  if pending == nil then
    return false
  end
  local doc_row = begin_document_row(bufnr)
  return doc_row ~= nil and pending.start_row <= doc_row
end

local function display_kind_for_backend_node(node_type)
  if node_type == "inline_formula" then
    return "inline"
  end
  return "block"
end

local function sort_units(units)
  table.sort(units, function(a, b)
    if a.range[1] ~= b.range[1] then
      return a.range[1] < b.range[1]
    end
    if a.range[2] ~= b.range[2] then
      return a.range[2] < b.range[2]
    end
    if a.range[3] ~= b.range[3] then
      return a.range[3] < b.range[3]
    end
    return a.range[4] < b.range[4]
  end)
  return units
end

local function build_entries(bufnr, units)
  local entries = {}
  for _, unit in ipairs(sort_units(units or {})) do
    local source = range_to_string(bufnr, unit.range)
    local backend_node_type = unit.backend_node_type or "inline_formula"
    local display_kind = display_kind_for_backend_node(backend_node_type)
    entries[#entries + 1] = {
      range = unit.range,
      display_range = unit.range,
      prelude_count = 0,
      node_type = "math",
      backend_node_type = backend_node_type,
      source_text = source,
      stable_key = table.concat({
        "latex",
        backend_node_type,
        tostring(unit.range[1]),
        tostring(unit.range[2]),
        tostring(unit.range[3]),
        tostring(unit.range[4]),
      }, ":"),
      semantics = {
        backend_id = "latex",
        backend_node_type = backend_node_type,
        constraint_kind = "intrinsic",
        display_kind = display_kind,
        source_kind = "latex",
      },
      source_hash = hash_string(source),
    }
  end
  return entries
end

--- @param bufnr integer
--- @param opts table|nil
--- @return table[] entries, table[] units
function M.collect(bufnr, opts)
  opts = opts or {}
  local parser = opts.parser or vim.treesitter.get_parser(bufnr, "latex")
  local root = parser:parse()[1]:root()
  local query = get_query()
  local prev_units = opts.prev_units
  local pending = opts.pending_change
  local units

  if
    prev_units ~= nil
    and pending ~= nil
    and not pending.requires_full
    and not pending_touches_preamble(bufnr, pending)
  then
    local start_row, end_row = expand_rows_to_cover_units(prev_units, pending.start_row, pending.new_end_row)
    local match_index = build_match_index(bufnr, root, query, start_row, end_row + 1)
    local new_units = collect_top_level_units(root, match_index, start_row, end_row)
    units = merge_units_in_rows(prev_units, new_units, start_row, end_row)
  else
    local match_index = build_match_index(bufnr, root, query)
    units = collect_top_level_units(root, match_index)
  end

  units = sort_units(units)
  return build_entries(bufnr, units), units
end

function M.render_viewport()
  local ok, main = pcall(require, "math-conceal.image")
  local latex_config = ok and main.config and main.config.backends and main.config.backends.latex or {}
  return {
    kind = "visible",
    margin = latex_config.viewport_margin or 0,
  }
end

function M.render_policy()
  local ok, main = pcall(require, "math-conceal.image")
  local latex_config = ok and main.config and main.config.backends and main.config.backends.latex or {}
  return {
    kind = "progressive",
    margin = latex_config.viewport_margin or 0,
  }
end

return M
