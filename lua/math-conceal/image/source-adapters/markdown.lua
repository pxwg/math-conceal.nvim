--- Markdown math source adapter.
--- Collects LaTeX math ranges and converts them to Typst/MiTeX render text.

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

function M.render_viewport()
  return {
    kind = "visible",
    margin = 0,
  }
end

function M.render_policy()
  return {
    kind = "progressive",
    margin = 0,
  }
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

local function typst_string_literal(value)
  value = value or ""
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  return '"' .. value .. '"'
end

local function render_text(content, display_kind)
  if display_kind == "block" then
    return "#mitex(" .. typst_string_literal(content) .. ")"
  end
  return "#mi(" .. typst_string_literal(content) .. ")"
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

local function delimited_content(lines, range, spec)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local open_len = #spec.open
  local close_len = #spec.close

  if start_row == end_row then
    return (lines[start_row + 1] or ""):sub(start_col + open_len + 1, end_col - close_len)
  end

  local parts = {}
  parts[1] = (lines[start_row + 1] or ""):sub(start_col + open_len + 1)
  for row = start_row + 1, end_row - 1 do
    parts[#parts + 1] = lines[row + 1] or ""
  end
  parts[#parts + 1] = (lines[end_row + 1] or ""):sub(1, end_col - close_len)

  if spec.display_kind == "block" and parts[1] == "" then
    table.remove(parts, 1)
  end
  if spec.display_kind == "block" and parts[#parts] == "" then
    parts[#parts] = nil
  end
  return table.concat(parts, "\n")
end

local function spec_for_source(source)
  for _, spec in ipairs(delimiter_specs) do
    if source:sub(1, #spec.open) == spec.open and source:sub(-#spec.close) == spec.close then
      return spec
    end
  end
  return nil
end

local function push_entry(entries, lines, range, spec, content)
  entries[#entries + 1] = {
    range = range,
    display_range = range,
    prelude_count = 0,
    node_type = "math",
    source_text = original_text(lines, range),
    render_text = render_text(content, spec.display_kind),
    stable_key = table.concat({
      "markdown",
      spec.id,
      tostring(range[1]),
      tostring(range[2]),
      tostring(range[3]),
      tostring(range[4]),
    }, ":"),
    semantics = {
      constraint_kind = "intrinsic",
      display_kind = spec.display_kind,
      markdown_delimiter = spec.id,
      source_kind = "math",
      markdown_math = true,
    },
    requires_mitex = true,
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
  if markdown_parser == nil then
    return nil
  end

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
  if markdown_parser == nil then
    return nil
  end

  local query = get_markdown_inline_math_query()
  if query == nil then
    return nil
  end

  local inline_parsers = {}
  collect_target_parsers(markdown_parser, "markdown", "markdown_inline", inline_parsers)
  if #inline_parsers == 0 then
    return nil
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
            push_entry(entries, lines, range, spec, delimited_content(lines, range, spec))
          end
        end
      end
    end
  end

  return top_level_entries(entries)
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
  local in_fence = false

  while row < #lines do
    local line = lines[row + 1] or ""
    if shields == nil and (line:match("^%s*```") or line:match("^%s*~~~")) then
      in_fence = not in_fence
      row = row + 1
    elseif shields == nil and in_fence then
      row = row + 1
    else
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
          push_entry(entries, lines, range, spec, delimited_content(lines, range, spec))
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
end

--- @param bufnr integer
--- @return table[]
function M.collect(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = {}

  local markdown_parser = get_markdown_parser(bufnr)
  local ts_entries = collect_treesitter_math(bufnr, lines, markdown_parser)
  if ts_entries ~= nil then
    for _, entry in ipairs(ts_entries) do
      entries[#entries + 1] = entry
    end
  end

  local shields = collect_shield_ranges(bufnr, markdown_parser)
  local specs = ts_entries == nil and delimiter_specs or scanner_delimiter_specs
  collect_delimited_math(entries, lines, specs, shields)

  return top_level_entries(entries)
end

return M
