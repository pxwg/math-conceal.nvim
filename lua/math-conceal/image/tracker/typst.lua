local M = {}

local query = nil

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function le(a_row, a_col, b_row, b_col)
  return lt(a_row, a_col, b_row, b_col) or (a_row == b_row and a_col == b_col)
end

local function range_intersects(a, b)
  return lt(a.row, a.col, b.end_row, b.end_col) and lt(b.row, b.col, a.end_row, a.end_col)
end

local function range_equal(a, b)
  return a ~= nil
    and b ~= nil
    and a.row == b.row
    and a.col == b.col
    and a.end_row == b.end_row
    and a.end_col == b.end_col
end

local function is_blank(text)
  return (text or ""):match("^%s*$") ~= nil
end

local function source_hash(source)
  return vim.fn.sha256(source or "")
end

local builtin_code_calls = {
  align = true,
  block = true,
  box = true,
  circle = true,
  columns = true,
  ellipse = true,
  emph = true,
  enum = true,
  figure = true,
  grid = true,
  h = true,
  heading = true,
  highlight = true,
  image = true,
  line = true,
  linebreak = true,
  link = true,
  list = true,
  lorem = true,
  ["math.equation"] = true,
  move = true,
  overline = true,
  pad = true,
  pagebreak = true,
  parbreak = true,
  path = true,
  place = true,
  polygon = true,
  quote = true,
  raw = true,
  rect = true,
  rotate = true,
  scale = true,
  smallcaps = true,
  square = true,
  stack = true,
  strike = true,
  strong = true,
  table = true,
  terms = true,
  text = true,
  underline = true,
  v = true,
}

local builtin_code_field_roots = {
  emoji = true,
  sym = true,
}

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

local function first_named_child(node)
  if node == nil then
    return nil
  end
  for child in node:iter_children() do
    if child:named() then
      return child
    end
  end
  return nil
end

local function append_field_path(bufnr, node, out)
  if node == nil then
    return
  end
  local node_type = node:type()
  if node_type == "ident" then
    out[#out + 1] = vim.treesitter.get_node_text(node, bufnr)
    return
  end
  if node_type ~= "field" then
    return
  end
  for child in node:iter_children() do
    if child:named() and (child:type() == "field" or child:type() == "ident") then
      append_field_path(bufnr, child, out)
    end
  end
end

local function head_path(bufnr, node)
  if node == nil then
    return nil
  end
  local node_type = node:type()
  if node_type == "call" then
    return head_path(bufnr, first_named_child(node))
  end
  if node_type == "ident" then
    return { vim.treesitter.get_node_text(node, bufnr) }
  end
  if node_type == "field" then
    local path = {}
    append_field_path(bufnr, node, path)
    if #path > 0 then
      return path
    end
  end
  return nil
end

local function code_candidate(bufnr, node)
  local path = head_path(bufnr, node)
  local node_type = node and node:type() or "unknown"
  local kind = node_type
  if node_type ~= "call" and node_type ~= "field" and node_type ~= "ident" then
    kind = "unknown"
  end
  return {
    kind = kind,
    path = path,
    root = path and path[1] or nil,
    name = path and table.concat(path, ".") or nil,
  }
end

local function add_code_name(out, value)
  if type(value) == "string" and value ~= "" then
    out[value] = true
    return
  end
  if type(value) ~= "table" then
    return
  end
  for _, key in ipairs({ "name", "call", "field", "ident" }) do
    if type(value[key]) == "string" and value[key] ~= "" then
      out[value[key]] = true
    end
  end
end

local function configured_code_names(values)
  local out = {}
  if type(values) == "string" then
    add_code_name(out, values)
  elseif type(values) == "table" then
    if vim.islist(values) then
      for _, value in ipairs(values) do
        add_code_name(out, value)
      end
    else
      for key, value in pairs(values) do
        if type(key) == "string" and value == true then
          add_code_name(out, key)
        else
          add_code_name(out, value)
        end
      end
    end
  end
  return out
end

local function configured_code_policy()
  local ok, image = pcall(require, "math-conceal.image")
  local renderer_cfg = nil
  if ok and type(image) == "table" and type(image.config) == "table" and type(image.config.renderers) == "table" then
    renderer_cfg = image.config.renderers.typst
  end
  local code_cfg = type(renderer_cfg) == "table" and renderer_cfg.code_render or nil
  return {
    allow = configured_code_names(
      type(code_cfg) == "table" and (code_cfg.allow or code_cfg.allowlist or code_cfg.whitelist) or nil
    ),
    exclude = configured_code_names(type(code_cfg) == "table" and code_cfg.exclude or nil),
  }
end

local function path_uses_with(path)
  return type(path) == "table" and #path >= 2 and path[2] == "with"
end

local function exact_matches_names(unit, names)
  return type(names) == "table" and unit.code_name ~= nil and names[unit.code_name] == true
end

local function call_matches_names(unit, names)
  if type(names) ~= "table" or unit.code_kind ~= "call" then
    return false
  end
  if exact_matches_names(unit, names) then
    return true
  end
  if path_uses_with(unit.code_path) and names[unit.code_root] == true then
    return true
  end
  return false
end

local function is_builtin_renderable_code(unit)
  if unit.code_kind == "field" and unit.code_root ~= nil and builtin_code_field_roots[unit.code_root] == true then
    return true
  end
  return call_matches_names(unit, builtin_code_calls)
end

local function is_user_renderable_code(unit, names)
  return call_matches_names(unit, names) or exact_matches_names(unit, names)
end

local function is_excluded_code(unit, names)
  if call_matches_names(unit, names) or exact_matches_names(unit, names) then
    return true
  end
  return type(names) == "table"
    and unit.code_kind == "field"
    and unit.code_root ~= nil
    and names[unit.code_root] == true
end

local function is_renderable_code_unit(unit, policy)
  if is_excluded_code(unit, policy.exclude) then
    return false
  end
  return is_builtin_renderable_code(unit) or is_user_renderable_code(unit, policy.allow)
end

local function show_has_selector(node)
  return node ~= nil and node:type() == "show" and node:named_child_count() >= 2
end

local function build_match_index(bufnr, root, parsed_query, start_row, end_row)
  local index = {}

  for _, match in parsed_query:iter_matches(root, bufnr, start_row or 0, end_row or -1, { all = true }) do
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
        object_kind = math_node ~= nil and "math" or "code",
        node_type = math_node ~= nil and "math" or node:type(),
        row = range.row,
        col = range.col,
        end_row = range.end_row,
        end_col = range.end_col,
      }

      if code_node ~= nil then
        local candidate = code_candidate(bufnr, code_node)
        entry.object_kind = "code"
        entry.node_type = "code"
        entry.code_type = code_node:type()
        entry.code_kind = candidate.kind
        entry.code_name = candidate.name
        entry.code_root = candidate.root
        entry.code_path = candidate.path
        entry.call_ident = call_ident_node and vim.treesitter.get_node_text(call_ident_node, bufnr) or ""
        if entry.code_type == "show" then
          entry.show_has_selector = show_has_selector(code_node)
        end
      end

      index[node:id()] = entry
    end
  end

  return index
end

local function sort_units(units)
  table.sort(units, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return (a.node and a.node:id() or 0) < (b.node and b.node:id() or 0)
  end)
  return units
end

local function same_container_entry(entry, container)
  if entry == nil or container == nil then
    return false
  end
  if not range_equal(entry, container) then
    return false
  end
  local entry_kind = entry.object_kind or entry.node_type or "math"
  local container_kind = container.object_kind or container.node_type or "math"
  return entry_kind == container_kind
end

local function find_container_entry(match_index, container)
  for _, entry in pairs(match_index) do
    if same_container_entry(entry, container) then
      return entry
    end
  end
  return nil
end

local function context_kind(unit)
  if unit.object_kind ~= "code" then
    return nil
  end
  if unit.code_type == "let" or unit.code_type == "set" or unit.code_type == "import" then
    return unit.code_type
  end
  if unit.code_type == "show" then
    if unit.show_has_selector == true then
      return "show"
    end
    return nil
  end
  if unit.call_ident == "import" then
    return "import"
  end
  return nil
end

local function is_context_unit(_, unit)
  local kind = context_kind(unit)
  if kind == nil then
    return false
  end
  return true
end

local function append_visible_units_from_node(
  node,
  match_index,
  code_policy,
  opts,
  units,
  transparent_depth,
  include_self
)
  if node == nil then
    return
  end

  transparent_depth = transparent_depth or 0
  local entry = include_self ~= false and match_index[node:id()] or nil
  if entry ~= nil then
    if entry.object_kind == "math" then
      units[#units + 1] = entry
      return
    end
    if is_context_unit(nil, entry) then
      if opts.collect_context == true and transparent_depth == 0 then
        units[#units + 1] = entry
      end
      return
    end
    if entry.object_kind == "code" and is_renderable_code_unit(entry, code_policy) then
      units[#units + 1] = entry
      return
    end

    transparent_depth = transparent_depth + 1
  end

  for child in node:iter_children() do
    if child:named() then
      append_visible_units_from_node(child, match_index, code_policy, opts, units, transparent_depth, true)
    end
  end
end

local function collect_visible_units(root, match_index, code_policy, opts)
  local units = {}
  append_visible_units_from_node(root, match_index, code_policy, opts or {}, units, 0, true)
  return sort_units(units)
end

local function collect_nested_visible_units(container_entry, match_index, code_policy)
  local units = {}
  if container_entry == nil or container_entry.node == nil then
    return units
  end

  for child in container_entry.node:iter_children() do
    if child:named() then
      append_visible_units_from_node(child, match_index, code_policy, { collect_context = false }, units, 0, true)
    end
  end
  return sort_units(units)
end

local function math_source_display_facts(bufnr, unit, source, display)
  local source_rows = unit.end_row - unit.row + 1
  local source_facts = {
    source_kind = "typst",
    object_kind = "math",
    break_line = source_rows > 1,
  }

  if display == nil then
    display = (source:match("^%$%s+") ~= nil and source:match("%s+%$$") ~= nil) and "block" or "inline"
  end
  if display == "block" then
    local start_line = vim.api.nvim_buf_get_lines(bufnr, unit.row, unit.row + 1, false)[1] or ""
    local end_line = vim.api.nvim_buf_get_lines(bufnr, unit.end_row, unit.end_row + 1, false)[1] or ""
    local prefix = start_line:sub(1, unit.col)
    local suffix = end_line:sub(unit.end_col + 1)
    local isolated = is_blank(prefix) and is_blank(suffix)
    source_facts.display_kind = "block"
    source_facts.inline = false
    source_facts.isolated = isolated
    return "block", isolated, source_rows, source_facts
  end

  source_facts.display_kind = "inline"
  source_facts.inline = true
  source_facts.isolated = false
  return "inline", false, source_rows, source_facts
end

local function code_source_display_facts(unit, geometry)
  geometry = geometry or unit
  local source_rows = geometry.end_row - geometry.row + 1
  return "unknown",
    false,
    source_rows,
    {
      source_kind = "typst",
      object_kind = "code",
      code_kind = unit.code_kind,
      code_name = unit.code_name,
      code_path = unit.code_path,
      break_line = source_rows > 1,
    }
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

local function context_signature(kind, source)
  return vim.fn.sha256(table.concat({
    kind or "",
    source or "",
  }, "\0"))
end

local function context_record(bufnr, unit)
  local source = range_source(bufnr, unit)
  local kind = context_kind(unit)
  return {
    index = 0,
    kind = kind,
    row = unit.row,
    col = unit.col,
    end_row = unit.end_row,
    end_col = unit.end_col,
    source = source,
    source_hash = source_hash(source),
    signature = context_signature(kind, source),
  }
end

-- `unit` is the compiled source range. `geometry`, when given, is the wider
-- track range (an injected region including its delimiter lines); the source
-- start is then recorded relative to the track in source_facts.source_offset.
local function node_record(bufnr, unit, context_units, prefixes, display, geometry)
  geometry = geometry or unit
  local source = range_source(bufnr, unit)
  local object_kind = unit.object_kind or unit.node_type or "math"
  local source_display_kind, render_whole_line, source_rows, source_facts
  if object_kind == "code" then
    source_display_kind, render_whole_line, source_rows, source_facts = code_source_display_facts(unit, geometry)
  else
    object_kind = "math"
    source_display_kind, render_whole_line, source_rows, source_facts =
      math_source_display_facts(bufnr, geometry, source, display)
  end
  if geometry.row ~= unit.row or geometry.col ~= unit.col then
    local rows = unit.row - geometry.row
    -- Same-row offsets are relative to the track column, later rows absolute.
    source_facts.source_offset = { rows = rows, col = rows == 0 and unit.col - geometry.col or unit.col }
  end
  local prelude_count = 0
  for idx, context_unit in ipairs(context_units or {}) do
    if le(context_unit.end_row, context_unit.end_col, geometry.row, geometry.col) then
      prelude_count = idx
    else
      break
    end
  end

  return {
    kind = "typst",
    source_kind = "typst",
    object_kind = object_kind,
    node_type = object_kind,
    row = geometry.row,
    col = geometry.col,
    end_row = geometry.end_row,
    end_col = geometry.end_col,
    source = source,
    source_hash = source_hash(source),
    source_rows = source_rows,
    source_display_kind = source_display_kind,
    source_facts = source_facts,
    render_whole_line = render_whole_line,
    prelude_count = prelude_count,
    prelude_signature = prefixes[prelude_count] or prefixes[0],
  }
end

local function query_or_error()
  local parsed_query, query_err = get_query()
  if parsed_query == nil then
    error("failed to parse Typst math tracker query: " .. tostring(query_err))
  end
  return parsed_query
end

local function line_text(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
end

-- Root language of the buffer's syntax tree. Typst buffers (and buffers whose
-- filetype has no other parser) use Typst; any other host scans its Typst
-- injections.
local function host_lang_for(filetype)
  if filetype == nil or filetype == "" then
    return "typst"
  end
  local lang = vim.treesitter.language.get_lang(filetype) or filetype
  if lang == "typst" then
    return "typst"
  end
  local ok, added = pcall(vim.treesitter.language.add, lang)
  if not ok or not added then
    return "typst"
  end
  return lang
end

-- A Typst injection region. A region occupying whole lines (a source block
-- body) is a block: its track also covers the line before and after it, the
-- host's delimiter lines, while only the body is compiled.
local function injected_region(bufnr, ranges, tree)
  local row, col, end_row, end_col
  if type(ranges) == "table" and #ranges > 0 then
    local first, last = ranges[1], ranges[#ranges]
    row, col, end_row, end_col = first[1], first[2], last[4], last[5]
  else
    row, col, end_row, end_col = tree:root():range()
  end
  local body = { row = row, col = col, end_row = end_row, end_col = end_col }
  local whole_lines = end_col == 0 and end_row > row and is_blank(line_text(bufnr, row):sub(1, col))
  if whole_lines then
    body.end_row = end_row - 1
    body.end_col = #line_text(bufnr, body.end_row)
  end
  if not lt(body.row, body.col, body.end_row, body.end_col) then
    return nil
  end
  local track = body
  if whole_lines and row > 0 and end_row < vim.api.nvim_buf_line_count(bufnr) then
    track = { row = row - 1, col = 0, end_row = end_row, end_col = #line_text(bufnr, end_row) }
  end
  return { body = body, track = track, block = whole_lines }
end

-- Typst syntax roots of a buffer: the root tree of a Typst buffer, or every
-- Typst injection region of a host buffer in document order.
local function typst_roots(bufnr, host_lang, parse_range)
  if host_lang == "typst" then
    local parser = vim.treesitter.get_parser(bufnr, "typst")
    local tree = parser:parse()[1]
    return tree and { { root = tree:root() } } or {}
  end

  local parser = vim.treesitter.get_parser(bufnr, host_lang, { error = false })
  if parser == nil then
    return {}
  end
  parser:parse(parse_range or true)

  local roots = {}
  local function visit(ltree)
    for lang, child in pairs(ltree:children()) do
      if lang == "typst" then
        local regions = child:included_regions()
        for idx, tree in pairs(child:trees()) do
          local region = injected_region(bufnr, regions[idx], tree)
          if region ~= nil then
            roots[#roots + 1] = { root = tree:root(), region = region }
          end
        end
      else
        visit(child)
      end
    end
  end
  visit(parser)
  table.sort(roots, function(a, b)
    return lt(a.region.track.row, a.region.track.col, b.region.track.row, b.region.track.col)
  end)
  return roots
end

local function root_units(bufnr, entry, parsed_query, code_policy, start_row, end_row)
  local match_index = build_match_index(bufnr, entry.root, parsed_query, start_row, end_row)
  local units = collect_visible_units(entry.root, match_index, code_policy, { collect_context = true })
  return units, match_index
end

local function is_display_math_source(source)
  return source:match("^%$%s+") ~= nil and source:match("%s+%$$") ~= nil
end

local function strip_context_sources(bufnr, body_source, units)
  local rest = body_source
  for _, unit in ipairs(units) do
    if is_context_unit(bufnr, unit) then
      local text = range_source(bufnr, unit)
      local start = rest:find(text, 1, true)
      if start ~= nil then
        rest = rest:sub(1, start - 1) .. rest:sub(start + #text)
      end
    end
  end
  return rest
end

-- The render node of an injected region, or nil for a region that only holds
-- context. A region that is exactly one formula keeps the math semantics
-- (display math in a block region renders as display math); any other region
-- is Typst markup, a code node whose inline/block role flow layout decides.
-- Returns the node and the container entry used for cursor-nested scans.
local function region_node(bufnr, entry, units, context_units, prefixes)
  local region = entry.region
  local body_source = range_source(bufnr, region.body)
  if is_blank(strip_context_sources(bufnr, body_source, units)) then
    return nil
  end

  local only = #units == 1 and units[1] or nil
  if only ~= nil and only.object_kind == "math" and vim.trim(body_source) == range_source(bufnr, only) then
    if not region.block then
      return node_record(bufnr, only, context_units, prefixes), only
    end
    if is_display_math_source(range_source(bufnr, only)) then
      return node_record(bufnr, only, context_units, prefixes, "block", region.track), only
    end
  end

  local unit = {
    row = region.body.row,
    col = region.body.col,
    end_row = region.body.end_row,
    end_col = region.body.end_col,
    object_kind = "code",
    node_type = "code",
    code_kind = "region",
  }
  return node_record(bufnr, unit, context_units, prefixes, nil, region.track), { node = entry.root }
end

local function context_records(bufnr, units, window)
  local records = {}
  for _, unit in ipairs(units) do
    if is_context_unit(bufnr, unit) and (window == nil or range_intersects(unit, window)) then
      records[#records + 1] = context_record(bufnr, unit)
    end
  end
  table.sort(records, function(a, b)
    return lt(a.row, a.col, b.row, b.col)
  end)
  for idx, record in ipairs(records) do
    record.index = idx
  end
  return records
end

local function is_render_unit(bufnr, unit, code_policy)
  if unit.object_kind == "math" then
    return true
  end
  return not is_context_unit(bufnr, unit) and unit.object_kind == "code" and is_renderable_code_unit(unit, code_policy)
end

local function empty_scan()
  return { nodes = {}, context_units = {}, context_signature = vim.fn.sha256("") }
end

local function build_scan(bufnr, host_lang)
  local parsed_query = query_or_error()
  local roots = typst_roots(bufnr, host_lang)
  if #roots == 0 then
    return empty_scan()
  end

  local code_policy = configured_code_policy()
  local scanned, all_units = {}, {}
  for _, entry in ipairs(roots) do
    local units = root_units(bufnr, entry, parsed_query, code_policy)
    scanned[#scanned + 1] = { entry = entry, units = units }
    vim.list_extend(all_units, units)
  end

  -- Context units are shared across regions in document order.
  local context_units = context_records(bufnr, all_units)
  local prefixes = prefix_signatures(context_units)
  local nodes = {}
  for _, item in ipairs(scanned) do
    if item.entry.region ~= nil then
      local node = region_node(bufnr, item.entry, item.units, context_units, prefixes)
      if node ~= nil then
        nodes[#nodes + 1] = node
      end
    else
      for _, unit in ipairs(item.units) do
        if is_render_unit(bufnr, unit, code_policy) then
          nodes[#nodes + 1] = node_record(bufnr, unit, context_units, prefixes)
        end
      end
    end
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

local function build_window_scan(bufnr, host_lang, window, context_units)
  local parsed_query = query_or_error()
  context_units = context_units or {}
  local roots = typst_roots(bufnr, host_lang, { math.max(0, window.row - 1), window.end_row + 2 })
  local code_policy = configured_code_policy()
  local prefixes = prefix_signatures(context_units)
  local nodes, local_units = {}, {}

  for _, entry in ipairs(roots) do
    if entry.region == nil then
      local units = root_units(bufnr, entry, parsed_query, code_policy, window.row, window.end_row + 1)
      for _, unit in ipairs(units) do
        if range_intersects(unit, window) then
          if is_render_unit(bufnr, unit, code_policy) then
            nodes[#nodes + 1] = node_record(bufnr, unit, context_units, prefixes)
          else
            local_units[#local_units + 1] = unit
          end
        end
      end
    elseif range_intersects(entry.region.track, window) then
      local units = root_units(bufnr, entry, parsed_query, code_policy)
      local node = region_node(bufnr, entry, units, context_units, prefixes)
      if node ~= nil and range_intersects(node, window) then
        nodes[#nodes + 1] = node
      end
      vim.list_extend(local_units, units)
    end
  end

  return {
    nodes = nodes,
    context_units = context_records(bufnr, local_units, window),
  }
end

-- Container entry of a cursor-nested scan: an injected region rendered as a
-- whole, or a math/code unit inside a Typst root.
local function nested_container(bufnr, host_lang, container, parsed_query, code_policy, context_units)
  local roots = typst_roots(bufnr, host_lang, { container.row, container.end_row + 1 })
  local prefixes = prefix_signatures(context_units)
  for _, entry in ipairs(roots) do
    local region = entry.region
    local covers = region == nil
      or le(region.track.row, region.track.col, container.row, container.col)
        and le(container.end_row, container.end_col, region.track.end_row, region.track.end_col)
    if covers then
      local units, match_index = root_units(bufnr, entry, parsed_query, code_policy)
      if region ~= nil then
        local node, container_entry = region_node(bufnr, entry, units, context_units, prefixes)
        if node ~= nil and range_equal(node, container) then
          return container_entry, match_index
        end
      end
      local found = find_container_entry(match_index, container)
      if found ~= nil then
        return found, match_index
      end
    end
  end
  return nil, nil
end

local function build_nested_scan(bufnr, host_lang, container, context_units)
  local parsed_query = query_or_error()
  context_units = context_units or {}
  local code_policy = configured_code_policy()
  local container_entry, match_index =
    nested_container(bufnr, host_lang, container, parsed_query, code_policy, context_units)
  if container_entry == nil then
    return { nodes = {}, context_units = {} }
  end

  local units = collect_nested_visible_units(container_entry, match_index, code_policy)
  local prefixes = prefix_signatures(context_units)
  local nodes = {}
  for _, unit in ipairs(units) do
    if is_render_unit(bufnr, unit, code_policy) then
      nodes[#nodes + 1] = node_record(bufnr, unit, context_units, prefixes)
    end
  end

  return {
    nodes = nodes,
    context_units = {},
  }
end

local function scanner(host_lang_of)
  local S = {}

  ---@param bufnr integer
  ---@return table
  function S.scan_all(bufnr)
    return build_scan(bufnr, host_lang_of())
  end

  ---@param bufnr integer
  ---@return table
  function S.scan_context(bufnr)
    local scan = build_scan(bufnr, host_lang_of())
    return {
      units = scan.context_units,
      signature = scan.context_signature,
    }
  end

  ---@param bufnr integer
  ---@param window {row: integer, col: integer, end_row: integer, end_col: integer}
  ---@return table
  function S.scan(bufnr, window, context_units)
    return build_window_scan(bufnr, host_lang_of(), window, context_units)
  end

  ---@param bufnr integer
  ---@param container table
  ---@return table
  function S.scan_nested(bufnr, container, context_units)
    return build_nested_scan(bufnr, host_lang_of(), container, context_units)
  end

  return S
end

---Typst scanner for a buffer of `opts.filetype`. A Typst filetype scans the
---root tree; a host filetype with its own parser (Org, Markdown, ...) scans
---every Typst injection region of the host tree.
---@param opts {filetype: string?}?
---@return table
function M.new(opts)
  local filetype = (opts or {}).filetype
  return scanner(function()
    return host_lang_for(filetype)
  end)
end

-- Module-level scanner functions scan Typst buffers.
local typst_scanner = scanner(function()
  return "typst"
end)
M.scan_all = typst_scanner.scan_all
M.scan_context = typst_scanner.scan_context
M.scan = typst_scanner.scan
M.scan_nested = typst_scanner.scan_nested

local function is_index(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function range_error(range)
  if type(range) ~= "table" then
    return "range must be a table"
  end
  for _, key in ipairs({ "row", "col", "end_row", "end_col" }) do
    if not is_index(range[key]) then
      return ("range.%s must be a non-negative integer"):format(key)
    end
  end
  if lt(range.end_row, range.end_col, range.row, range.col) then
    return "range end precedes range start"
  end
  return nil
end

-- Internal: half-open intersection rule for scanner repair windows.
function M._range_intersects(a, b)
  return range_intersects(a, b)
end

local function field_error(value, key, expected)
  local actual = value[key]
  if expected == "index" then
    return not is_index(actual) and ("%s must be a non-negative integer"):format(key) or nil
  end
  if type(actual) ~= expected then
    return ("%s must be %s, got %s"):format(key, expected, type(actual))
  end
  return nil
end

local node_fields = {
  { "kind", "string" },
  { "source_kind", "string" },
  { "object_kind", "string" },
  { "node_type", "string" },
  { "source", "string" },
  { "source_hash", "string" },
  { "source_rows", "index" },
  { "source_display_kind", "string" },
  { "source_facts", "table" },
  { "render_whole_line", "boolean" },
  { "prelude_count", "index" },
  { "prelude_signature", "string" },
}

local source_fact_fields = {
  { "source_kind", "string" },
  { "object_kind", "string" },
  { "display_kind", "string" },
  { "inline", "boolean" },
  { "isolated", "boolean" },
  { "break_line", "boolean" },
}

---Internal: validate a node returned by a scanner factory.
---@param node table
---@return boolean ok
---@return string? err
function M._validate_node(node)
  if type(node) ~= "table" then
    return false, "must be a table"
  end
  local err = range_error(node)
  if err ~= nil then
    return false, err
  end
  for _, field in ipairs(node_fields) do
    err = field_error(node, field[1], field[2])
    if err ~= nil then
      return false, err
    end
  end
  for _, field in ipairs(source_fact_fields) do
    err = field_error(node.source_facts, field[1], field[2])
    if err ~= nil then
      return false, "source_facts." .. err
    end
  end
  if node.kind ~= "typst" or node.source_kind ~= "typst" or node.source_facts.source_kind ~= "typst" then
    return false, "kind, source_kind and source_facts.source_kind must be typst"
  end
  if node.object_kind ~= "math" or node.node_type ~= "math" or node.source_facts.object_kind ~= "math" then
    return false, "external Typst scanners support only math nodes"
  end
  if node.source_display_kind ~= "inline" and node.source_display_kind ~= "block" then
    return false, "source_display_kind must be inline or block"
  end
  if node.source_facts.display_kind ~= node.source_display_kind then
    return false, "source_facts.display_kind must match source_display_kind"
  end
  if node.source_hash ~= source_hash(node.source) then
    return false, "source_hash does not match source"
  end
  return true
end

---Internal: validate a context unit returned by a scanner factory.
---@param unit table
---@return boolean ok
---@return string? err
function M._validate_context_unit(unit)
  if type(unit) ~= "table" then
    return false, "must be a table"
  end
  local err = range_error(unit)
  if err ~= nil then
    return false, err
  end
  for _, field in ipairs({ { "source", "string" }, { "signature", "string" } }) do
    err = field_error(unit, field[1], field[2])
    if err ~= nil then
      return false, err
    end
  end
  return true
end

return M
