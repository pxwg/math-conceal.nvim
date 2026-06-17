local M = {}

local query = nil

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function source_hash(source)
  return vim.fn.sha256(source or "")
end

local function range_source(bufnr, range)
  local lines = vim.api.nvim_buf_get_lines(bufnr, range.row, range.end_row + 1, false)
  if #lines == 0 then
    return ""
  end
  if range.row == range.end_row then
    lines[1] = lines[1]:sub(range.col + 1, range.end_col)
  else
    lines[1] = lines[1]:sub(range.col + 1)
    lines[#lines] = lines[#lines]:sub(1, range.end_col)
  end
  return table.concat(lines, "\n")
end

local function get_query()
  if query ~= nil then
    return query
  end

  local ok, parsed = pcall(
    vim.treesitter.query.parse,
    "typst",
    [[
[
 (code
  [(_) (call item: (ident) @call_ident)] @code
 )
 (math) @math
] @block
]]
  )
  if not ok then
    return nil, parsed
  end

  query = parsed
  return query
end

local function node_range(node)
  local row, col, end_row, end_col = node:range()
  return {
    row = row,
    col = col,
    end_row = end_row,
    end_col = end_col,
  }
end

local function capture_node(match, capture_id)
  local value = match[capture_id]
  if type(value) == "table" then
    return value[1]
  end
  return value
end

local function build_match_index(bufnr, root, parsed_query)
  local index = {}

  for _, match in parsed_query:iter_matches(root, bufnr, 0, -1, { all = true }) do
    local block_node = nil
    local code_node = nil
    local math_node = nil
    local call_ident_node = nil

    for capture_id, _ in pairs(match) do
      local name = parsed_query.captures[capture_id]
      local node = capture_node(match, capture_id)
      if name == "block" then
        block_node = node
      elseif name == "code" then
        code_node = node
      elseif name == "math" then
        math_node = node
      elseif name == "call_ident" then
        call_ident_node = node
      end
    end

    local node = block_node or math_node or code_node
    if node ~= nil then
      local range = node_range(node)
      local entry = {
        node = node,
        node_type = math_node ~= nil and "math" or node:type(),
        row = range.row,
        col = range.col,
        end_row = range.end_row,
        end_col = range.end_col,
      }

      if code_node ~= nil then
        entry.node_type = "code"
        entry.code_type = code_node:type()
        entry.call_ident = call_ident_node and vim.treesitter.get_node_text(call_ident_node, bufnr) or ""
      end

      index[node:id()] = entry
    end
  end

  return index
end

local function collect_top_level_units(root, match_index)
  local units = {}

  local function visit(node)
    if node == nil then
      return
    end

    local entry = match_index[node:id()]
    if entry ~= nil then
      units[#units + 1] = entry
      return
    end

    for child in node:iter_children() do
      if child:named() then
        visit(child)
      end
    end
  end

  visit(root)
  table.sort(units, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return (a.node and a.node:id() or 0) < (b.node and b.node:id() or 0)
  end)
  return units
end

local function context_kind(unit)
  if unit.node_type ~= "code" then
    return nil
  end
  if unit.code_type == "let" or unit.code_type == "set" or unit.code_type == "import" then
    return unit.code_type
  end
  if unit.code_type == "show" then
    return "show"
  end
  if unit.call_ident == "import" then
    return "import"
  end
  return nil
end

local function is_context_unit(bufnr, unit)
  local kind = context_kind(unit)
  if kind == nil then
    return false
  end

  if kind == "show" then
    local source = range_source(bufnr, unit)
    -- Bare `#show: ...` is document-wide and usually not useful for isolated
    -- snippet rendering. Selector show rules such as `#show math...` stay.
    return not source:match("^%s*#%s*show%s*:")
  end

  return true
end

local function source_display_facts(bufnr, unit, source)
  local source_rows = unit.end_row - unit.row + 1
  if source_rows > 1 then
    return "block", false, source_rows
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, unit.row, unit.row + 1, false)[1] or ""
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  local is_display_math = source:match("^%$%s+") ~= nil and source:match("%s+%$$") ~= nil
  if is_display_math then
    return "block", trimmed ~= source, source_rows
  end

  return "inline", false, source_rows
end

local function prefix_signatures(context_units)
  local signatures = { [0] = vim.fn.sha256("") }
  local parts = {}
  for idx, unit in ipairs(context_units) do
    parts[#parts + 1] = unit.signature
    signatures[idx] = vim.fn.sha256(table.concat(parts, "\0"))
  end
  return signatures
end

local function build_scan(bufnr)
  local parsed_query, query_err = get_query()
  if parsed_query == nil then
    error("failed to parse Typst math tracker query: " .. tostring(query_err))
  end

  local parser = vim.treesitter.get_parser(bufnr, "typst")
  local tree = parser:parse()[1]
  if tree == nil then
    return {
      nodes = {},
      context_units = {},
      context_signature = vim.fn.sha256(""),
    }
  end

  local root = tree:root()
  local units = collect_top_level_units(root, build_match_index(bufnr, root, parsed_query))
  local nodes = {}
  local context_units = {}

  for _, unit in ipairs(units) do
    if unit.node_type == "math" then
      local source = range_source(bufnr, unit)
      local source_display_kind, render_whole_line, source_rows = source_display_facts(bufnr, unit, source)
      nodes[#nodes + 1] = {
        kind = "typst",
        node_type = "math",
        row = unit.row,
        col = unit.col,
        end_row = unit.end_row,
        end_col = unit.end_col,
        source = source,
        source_hash = source_hash(source),
        source_rows = source_rows,
        source_display_kind = source_display_kind,
        render_whole_line = render_whole_line,
        prelude_count = #context_units,
      }
    elseif is_context_unit(bufnr, unit) then
      local source = range_source(bufnr, unit)
      local kind = context_kind(unit)
      local signature = vim.fn.sha256(table.concat({
        kind or "",
        tostring(unit.row),
        tostring(unit.col),
        tostring(unit.end_row),
        tostring(unit.end_col),
        source,
      }, "\0"))

      context_units[#context_units + 1] = {
        index = #context_units + 1,
        kind = kind,
        row = unit.row,
        col = unit.col,
        end_row = unit.end_row,
        end_col = unit.end_col,
        source = source,
        source_hash = source_hash(source),
        signature = signature,
      }
    end
  end

  local prefixes = prefix_signatures(context_units)
  for _, node in ipairs(nodes) do
    node.prelude_signature = prefixes[node.prelude_count] or prefixes[0]
  end

  local unit_signatures = {}
  for _, unit in ipairs(context_units) do
    unit_signatures[#unit_signatures + 1] = unit.signature
  end

  return {
    nodes = nodes,
    context_units = context_units,
    context_signature = vim.fn.sha256(table.concat(unit_signatures, "\0")),
  }
end

---@param bufnr integer
---@return table
function M.scan_all(bufnr)
  return build_scan(bufnr)
end

---@param bufnr integer
---@return table
function M.scan_context(bufnr)
  local scan = build_scan(bufnr)
  return {
    units = scan.context_units,
    signature = scan.context_signature,
  }
end

---@param bufnr integer
---@param window {row: integer, col: integer, end_row: integer, end_col: integer}
---@return table
function M.scan(bufnr, window)
  local scan = build_scan(bufnr)
  local nodes = {}
  for _, node in ipairs(scan.nodes) do
    if range_intersects(node, window) then
      nodes[#nodes + 1] = node
    end
  end
  scan.nodes = nodes
  return scan
end

return M
