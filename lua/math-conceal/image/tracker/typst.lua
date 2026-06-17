local M = {}

local query = nil

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function get_query()
  if query ~= nil then
    return query
  end

  local ok, parsed = pcall(vim.treesitter.query.parse, "typst", "(math) @math")
  if not ok then
    return nil, parsed
  end

  query = parsed
  return query
end

local function source_hash(source)
  return vim.fn.sha256(source or "")
end

local function node_record(bufnr, node)
  local row, col, end_row, end_col = node:range()
  local source = vim.treesitter.get_node_text(node, bufnr)

  return {
    kind = "typst",
    node_type = node:type(),
    row = row,
    col = col,
    end_row = end_row,
    end_col = end_col,
    source = source,
    source_hash = source_hash(source),
  }
end

---@param bufnr integer
---@param window {row: integer, col: integer, end_row: integer, end_col: integer}
---@return table[]
function M.scan(bufnr, window)
  local parsed_query, query_err = get_query()
  if parsed_query == nil then
    error("failed to parse Typst math tracker query: " .. tostring(query_err))
  end

  local parser = vim.treesitter.get_parser(bufnr, "typst")
  local tree = parser:parse()[1]
  if tree == nil then
    return {}
  end

  local root = tree:root()
  local nodes = {}

  for id, node in parsed_query:iter_captures(root, bufnr, window.row, window.end_row + 1) do
    if parsed_query.captures[id] == "math" then
      local record = node_record(bufnr, node)
      if range_intersects(record, window) then
        nodes[#nodes + 1] = record
      end
    end
  end

  table.sort(nodes, function(a, b)
    return lt(a.row, a.col, b.row, b.col)
  end)

  return nodes
end

return M
