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

local function add_allow_name(out, value)
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

local function configured_code_allowlist()
  local ok, image = pcall(require, "math-conceal.image")
  local renderer_cfg = nil
  if ok and type(image) == "table" and type(image.config) == "table" and type(image.config.renderers) == "table" then
    renderer_cfg = image.config.renderers.typst
  end
  local code_cfg = type(renderer_cfg) == "table" and renderer_cfg.code_render or nil
  local allow = type(code_cfg) == "table" and (code_cfg.allow or code_cfg.allowlist or code_cfg.whitelist) or nil
  local out = {}

  if type(allow) == "string" then
    add_allow_name(out, allow)
  elseif type(allow) == "table" then
    if vim.islist(allow) then
      for _, value in ipairs(allow) do
        add_allow_name(out, value)
      end
    else
      for key, value in pairs(allow) do
        if type(key) == "string" and value == true then
          add_allow_name(out, key)
        else
          add_allow_name(out, value)
        end
      end
    end
  end

  return out
end

local function path_uses_with(path)
  return type(path) == "table" and #path >= 2 and path[2] == "with"
end

local function exact_allowed_by_names(unit, names)
  return type(names) == "table" and unit.code_name ~= nil and names[unit.code_name] == true
end

local function call_allowed_by_names(unit, names)
  if type(names) ~= "table" or unit.code_kind ~= "call" then
    return false
  end
  if exact_allowed_by_names(unit, names) then
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
  return call_allowed_by_names(unit, builtin_code_calls)
end

local function is_user_renderable_code(unit, user_allowlist)
  return call_allowed_by_names(unit, user_allowlist) or exact_allowed_by_names(unit, user_allowlist)
end

local function is_renderable_code_unit(unit, user_allowlist)
  return is_builtin_renderable_code(unit) or is_user_renderable_code(unit, user_allowlist)
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

local function has_indexed_ancestor(node, match_index)
  local parent = node and node:parent() or nil
  while parent ~= nil do
    if match_index[parent:id()] ~= nil then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local function has_code_ancestor(node)
  local parent = node and node:parent() or nil
  while parent ~= nil do
    if parent:type() == "code" then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local function collect_local_top_level_units(match_index)
  local units = {}

  for _, entry in pairs(match_index) do
    if not has_indexed_ancestor(entry.node, match_index) and not has_code_ancestor(entry.node) then
      units[#units + 1] = entry
    end
  end

  table.sort(units, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return (a.node and a.node:id() or 0) < (b.node and b.node:id() or 0)
  end)

  return units
end

local function context_kind(unit)
  if unit.object_kind ~= "code" then
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

local function is_context_unit(_, unit)
  local kind = context_kind(unit)
  if kind == nil then
    return false
  end
  return true
end

local function math_source_display_facts(bufnr, unit, source)
  local source_rows = unit.end_row - unit.row + 1
  local source_facts = {
    source_kind = "typst",
    object_kind = "math",
    break_line = source_rows > 1,
  }

  local is_display_math = source:match("^%$%s+") ~= nil and source:match("%s+%$$") ~= nil
  if is_display_math then
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

local function code_source_display_facts(unit)
  local source_rows = unit.end_row - unit.row + 1
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

local function node_record(bufnr, unit, context_units, prefixes)
  local source = range_source(bufnr, unit)
  local object_kind = unit.object_kind or unit.node_type or "math"
  local source_display_kind, render_whole_line, source_rows, source_facts
  if object_kind == "code" then
    source_display_kind, render_whole_line, source_rows, source_facts = code_source_display_facts(unit)
  else
    object_kind = "math"
    source_display_kind, render_whole_line, source_rows, source_facts = math_source_display_facts(bufnr, unit, source)
  end
  local prelude_count = 0
  for idx, context_unit in ipairs(context_units or {}) do
    if le(context_unit.end_row, context_unit.end_col, unit.row, unit.col) then
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
    row = unit.row,
    col = unit.col,
    end_row = unit.end_row,
    end_col = unit.end_col,
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
  local user_code_allowlist = configured_code_allowlist()

  for _, unit in ipairs(units) do
    if unit.object_kind == "math" then
      local prefixes = prefix_signatures(context_units)
      nodes[#nodes + 1] = node_record(bufnr, unit, context_units, prefixes)
    elseif is_context_unit(bufnr, unit) then
      local record = context_record(bufnr, unit)
      record.index = #context_units + 1
      context_units[#context_units + 1] = record
    elseif unit.object_kind == "code" and is_renderable_code_unit(unit, user_code_allowlist) then
      local prefixes = prefix_signatures(context_units)
      nodes[#nodes + 1] = node_record(bufnr, unit, context_units, prefixes)
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

local function build_window_scan(bufnr, window, context_units)
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
    }
  end

  local root = tree:root()
  local units =
    collect_local_top_level_units(build_match_index(bufnr, root, parsed_query, window.row, window.end_row + 1))
  local prefixes = prefix_signatures(context_units or {})
  local nodes = {}
  local local_context_units = {}
  local user_code_allowlist = configured_code_allowlist()

  for _, unit in ipairs(units) do
    if unit.object_kind == "math" and range_intersects(unit, window) then
      nodes[#nodes + 1] = node_record(bufnr, unit, context_units or {}, prefixes)
    elseif is_context_unit(bufnr, unit) and range_intersects(unit, window) then
      local record = context_record(bufnr, unit)
      record.index = #local_context_units + 1
      local_context_units[#local_context_units + 1] = record
    elseif
      unit.object_kind == "code"
      and range_intersects(unit, window)
      and is_renderable_code_unit(unit, user_code_allowlist)
    then
      nodes[#nodes + 1] = node_record(bufnr, unit, context_units or {}, prefixes)
    end
  end

  return {
    nodes = nodes,
    context_units = local_context_units,
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
function M.scan(bufnr, window, context_units)
  return build_window_scan(bufnr, window, context_units)
end

return M
