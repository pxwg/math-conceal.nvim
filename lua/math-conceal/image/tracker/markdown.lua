local M = {}

local delimiter_specs = {
  {
    id = "dollar_block",
    open = "$$",
    close = "$$",
    display_kind = "block",
    multiline = true,
    tree_sitter = true,
  },
  {
    id = "dollar_inline",
    open = "$",
    close = "$",
    display_kind = "inline",
    multiline = false,
    tree_sitter = true,
  },
  {
    id = "bracket_block",
    open = "\\[",
    close = "\\]",
    display_kind = "block",
    multiline = true,
  },
  {
    id = "paren_inline",
    open = "\\(",
    close = "\\)",
    display_kind = "inline",
    multiline = false,
  },
}

local scanner_delimiter_specs = {}
for _, spec in ipairs(delimiter_specs) do
  if spec.tree_sitter ~= true then
    scanner_delimiter_specs[#scanner_delimiter_specs + 1] = spec
  end
end

local markdown_inline_math_query = nil
local markdown_shield_query = nil
local markdown_inline_shield_query = nil

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function range_table_intersects(range, window)
  return range_intersects({
    row = range[1],
    col = range[2],
    end_row = range[3],
    end_col = range[4],
  }, window)
end

local function source_hash(source)
  return vim.fn.sha256(source or "")
end

local function is_escaped(line, idx)
  local slash_count = 0
  local pos = idx - 1
  while pos >= 1 and line:sub(pos, pos) == "\\" do
    slash_count = slash_count + 1
    pos = pos - 1
  end
  return slash_count % 2 == 1
end

local function position_in_range(range, row, col)
  if row < range[1] or row > range[3] then
    return false
  end
  if row == range[1] and col < range[2] then
    return false
  end
  if row == range[3] and col >= range[4] then
    return false
  end
  return true
end

local function position_is_shielded(shields, row, col)
  for _, range in ipairs(shields or {}) do
    if row < range[1] then
      return false
    end
    if position_in_range(range, row, col) then
      return true
    end
  end
  return false
end

local function find_unescaped(line, needle, init, row, shields)
  local pos = init or 1
  while true do
    local found = line:find(needle, pos, true)
    if found == nil then
      return nil
    end
    if not is_escaped(line, found) and not position_is_shielded(shields, row, found - 1) then
      return found
    end
    pos = found + #needle
  end
end

local function original_text(lines, range)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  if start_row == end_row then
    return (lines[start_row + 1] or ""):sub(start_col + 1, end_col)
  end

  local parts = {}
  parts[1] = (lines[start_row + 1] or ""):sub(start_col + 1)
  for row = start_row + 1, end_row - 1 do
    parts[#parts + 1] = lines[row + 1] or ""
  end
  parts[#parts + 1] = (lines[end_row + 1] or ""):sub(1, end_col)
  return table.concat(parts, "\n")
end

local function content_range(range, spec)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local open_len = #spec.open
  local close_len = #spec.close
  if start_row == end_row then
    return {
      row = start_row,
      col = start_col + open_len,
      end_row = end_row,
      end_col = end_col - close_len,
    }
  end
  return {
    row = start_row,
    col = start_col + open_len,
    end_row = end_row,
    end_col = end_col - close_len,
  }
end

local function spec_for_source(source)
  for _, spec in ipairs(delimiter_specs) do
    if source:sub(1, #spec.open) == spec.open and source:sub(-#spec.close) == spec.close then
      return spec
    end
  end
  return nil
end

local function push_entry(entries, lines, range, spec)
  local source = original_text(lines, range)
  entries[#entries + 1] = {
    range = range,
    spec = spec,
    source = source,
  }
end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    local ar = a.range
    local br = b.range
    if ar[1] ~= br[1] then
      return ar[1] < br[1]
    end
    if ar[2] ~= br[2] then
      return ar[2] < br[2]
    end
    if ar[3] ~= br[3] then
      return ar[3] < br[3]
    end
    return ar[4] < br[4]
  end)
  return entries
end

local function range_contains_range(outer, inner)
  local starts_before_or_at = outer[1] < inner[1] or (outer[1] == inner[1] and outer[2] <= inner[2])
  local ends_after_or_at = outer[3] > inner[3] or (outer[3] == inner[3] and outer[4] >= inner[4])
  return starts_before_or_at and ends_after_or_at
end

local function top_level_entries(entries)
  local sorted = sort_entries(entries)
  local output = {}

  for _, entry in ipairs(sorted) do
    local keep = true
    local idx = #output
    while idx >= 1 do
      local previous = output[idx]
      if range_contains_range(previous.range, entry.range) then
        keep = false
        break
      end
      if range_contains_range(entry.range, previous.range) then
        table.remove(output, idx)
      end
      idx = idx - 1
    end

    if keep then
      output[#output + 1] = entry
    end
  end

  return sort_entries(output)
end

local function collect_target_parsers(parser, parser_lang, target_lang, parsers)
  if parser_lang == target_lang then
    parsers[#parsers + 1] = parser
  end

  local ok, children = pcall(function()
    return parser:children()
  end)
  if not ok or children == nil then
    return
  end

  for child_lang, child in pairs(children) do
    collect_target_parsers(child, child_lang, target_lang, parsers)
  end
end

local function get_markdown_parser(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or parser == nil then
    return nil
  end

  local parsed = pcall(function()
    parser:parse(true)
  end)
  if not parsed then
    return nil
  end

  return parser
end

local function parse_query(lang, query_text)
  local ok, query = pcall(vim.treesitter.query.parse, lang, query_text)
  if ok then
    return query
  end
  return nil
end

local function get_markdown_inline_math_query()
  if markdown_inline_math_query == nil then
    markdown_inline_math_query = parse_query(
      "markdown_inline",
      [[
(latex_block) @math
]]
    )
  end
  return markdown_inline_math_query
end

local function get_markdown_shield_query()
  if markdown_shield_query == nil then
    markdown_shield_query = parse_query(
      "markdown",
      [[
[
  (fenced_code_block)
  (indented_code_block)
] @shield
]]
    )
  end
  return markdown_shield_query
end

local function get_markdown_inline_shield_query()
  if markdown_inline_shield_query == nil then
    markdown_inline_shield_query = parse_query(
      "markdown_inline",
      [[
(code_span) @shield
]]
    )
  end
  return markdown_inline_shield_query
end

local function iter_parser_trees(parser)
  local ok, trees = pcall(function()
    parser:parse(true)
    return parser:trees()
  end)
  if not ok or trees == nil then
    return {}
  end
  return trees
end

local function collect_shield_ranges(bufnr, markdown_parser)
  local shields = {}
  local markdown_query = get_markdown_shield_query()
  if markdown_query ~= nil then
    for _, tree in ipairs(iter_parser_trees(markdown_parser)) do
      for _, node in markdown_query:iter_captures(tree:root(), bufnr, 0, -1) do
        shields[#shields + 1] = { node:range() }
      end
    end
  end

  local inline_query = get_markdown_inline_shield_query()
  if inline_query ~= nil then
    local inline_parsers = {}
    collect_target_parsers(markdown_parser, "markdown", "markdown_inline", inline_parsers)
    for _, parser in ipairs(inline_parsers) do
      for _, tree in ipairs(iter_parser_trees(parser)) do
        for _, node in inline_query:iter_captures(tree:root(), bufnr, 0, -1) do
          shields[#shields + 1] = { node:range() }
        end
      end
    end
  end

  table.sort(shields, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[2] < b[2]
  end)
  return shields
end

local function collect_treesitter_math(bufnr, lines, markdown_parser)
  local query = get_markdown_inline_math_query()
  if query == nil then
    return {}
  end

  local inline_parsers = {}
  collect_target_parsers(markdown_parser, "markdown", "markdown_inline", inline_parsers)
  if #inline_parsers == 0 then
    return {}
  end

  local entries = {}
  local seen = {}

  for _, parser in ipairs(inline_parsers) do
    for _, tree in ipairs(iter_parser_trees(parser)) do
      for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
        local range = { node:range() }
        local source = original_text(lines, range)
        local spec = spec_for_source(source)
        if spec ~= nil then
          local key = table.concat(range, ":")
          if not seen[key] then
            seen[key] = true
            push_entry(entries, lines, range, spec)
          end
        end
      end
    end
  end

  return entries
end

local function find_next_open(line, row, pos, specs, shields)
  local best_pos = nil
  local best_spec = nil

  for _, spec in ipairs(specs) do
    local found = find_unescaped(line, spec.open, pos, row, shields)
    if
      found ~= nil
      and (
        best_pos == nil
        or found < best_pos
        or (found == best_pos and best_spec ~= nil and #spec.open > #best_spec.open)
      )
    then
      best_pos = found
      best_spec = spec
    end
  end

  return best_spec, best_pos
end

local function find_close(lines, start_row, start_pos, spec, shields)
  local line = lines[start_row + 1] or ""
  local search_pos = start_pos + #spec.open
  local close_pos = find_unescaped(line, spec.close, search_pos, start_row, shields)
  if close_pos ~= nil and (spec.display_kind == "block" or close_pos > search_pos) then
    return start_row, close_pos + #spec.close - 1
  end

  if not spec.multiline then
    return nil, nil
  end

  local scan = start_row + 1
  while scan < #lines do
    close_pos = find_unescaped(lines[scan + 1] or "", spec.close, 1, scan, shields)
    if close_pos ~= nil then
      return scan, close_pos + #spec.close - 1
    end
    scan = scan + 1
  end

  return nil, nil
end

local function collect_delimited_math(entries, lines, specs, shields)
  local row = 0

  while row < #lines do
    local line = lines[row + 1] or ""
    local pos = 1
    local advanced_to_block_end = false

    while pos <= #line do
      local spec, start_pos = find_next_open(line, row, pos, specs, shields)
      if spec == nil or start_pos == nil then
        break
      end

      local end_row, end_col = find_close(lines, row, start_pos, spec, shields)
      if end_row ~= nil and end_col ~= nil then
        local range = { row, start_pos - 1, end_row, end_col }
        push_entry(entries, lines, range, spec)
        if end_row > row then
          row = end_row + 1
          advanced_to_block_end = true
          break
        end
        pos = end_col + 1
      else
        pos = start_pos + #spec.open
      end
    end

    if not advanced_to_block_end then
      row = row + 1
    end
  end
end

local function node_from_entry(entry)
  local range = entry.range
  local spec = entry.spec
  local content = content_range(range, spec)
  return {
    kind = "markdown",
    source_kind = "markdown",
    object_kind = "math",
    node_type = "math",
    row = range[1],
    col = range[2],
    end_row = range[3],
    end_col = range[4],
    source = entry.source,
    source_hash = source_hash(entry.source),
    source_rows = range[3] - range[1] + 1,
    source_display_kind = spec.display_kind,
    render_whole_line = false,
    prelude_count = 0,
    prelude_signature = vim.fn.sha256(""),
    source_facts = {
      source_kind = "markdown",
      object_kind = "math",
      delimiter = spec.id,
      display_kind = spec.display_kind,
      content_range = content,
      content_start_row = content.row,
      content_start_col = content.col,
      content_end_row = content.end_row,
      content_end_col = content.end_col,
    },
  }
end

local function collect_entries(bufnr)
  local markdown_parser = get_markdown_parser(bufnr)
  if markdown_parser == nil then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = collect_treesitter_math(bufnr, lines, markdown_parser)
  local shields = collect_shield_ranges(bufnr, markdown_parser)
  collect_delimited_math(entries, lines, scanner_delimiter_specs, shields)
  return top_level_entries(entries)
end

local function scan_entries(bufnr, window)
  local nodes = {}
  for _, entry in ipairs(collect_entries(bufnr)) do
    if window == nil or range_table_intersects(entry.range, window) then
      nodes[#nodes + 1] = node_from_entry(entry)
    end
  end
  return nodes
end

---@param bufnr integer
---@return table
function M.scan_all(bufnr)
  return {
    nodes = scan_entries(bufnr),
    context_units = {},
    context_signature = vim.fn.sha256(""),
  }
end

---@return table
function M.scan_context()
  return {
    units = {},
    signature = vim.fn.sha256(""),
  }
end

---@param bufnr integer
---@param window {row: integer, col: integer, end_row: integer, end_col: integer}
---@return table
function M.scan(bufnr, window)
  return {
    nodes = scan_entries(bufnr, window),
    context_units = {},
  }
end

return M
