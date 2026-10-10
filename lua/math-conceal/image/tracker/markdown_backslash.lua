local M = {}

local delimiter_specs = {
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

local markdown_shield_query
local markdown_inline_shield_query

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

function M.collect(bufnr, lines, markdown_parser, entries, helpers)
  local parse_query = helpers.parse_query
  local iter_parser_trees = helpers.iter_parser_trees
  local collect_target_parsers = helpers.collect_target_parsers
  local push_entry = helpers.push_entry

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

  local shields = collect_shield_ranges(bufnr, markdown_parser)
  collect_delimited_math(entries, lines, delimiter_specs, shields)
end

return M
