--- LaTeX document wrapper construction for service-backed formula rendering.

local M = {}

local function count_lines(text)
  text = text or ""
  if text == "" then
    return 0
  end
  local _, n = text:gsub("\n", "\n")
  if text:sub(-1) ~= "\n" then
    n = n + 1
  end
  return n
end

local function ensure_trailing_newline(text)
  text = text or ""
  if text == "" or text:sub(-1) == "\n" then
    return text
  end
  return text .. "\n"
end

local function typst_string_literal(value)
  value = value or ""
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  return '"' .. value .. '"'
end

local function normal_hex_color()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal" })
  if not ok or type(hl) ~= "table" or hl.fg == nil then
    return nil
  end
  return string.format("%06X", hl.fg)
end

local function configured_hex_color(config)
  local color = config and config.color or nil
  if type(color) == "string" then
    local hex = color:match("#([%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F])")
      or color:match("^([%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F])$")
    if hex ~= nil then
      return hex:upper()
    end
  end
  if config == nil or config.styling_type == nil or config.styling_type == "colorscheme" then
    return normal_hex_color()
  end
  return nil
end

local function default_packages(config)
  local parts = {
    "\\usepackage[active,tightpage]{preview}\n",
    "\\setlength\\PreviewBorder{0pt}\n",
    "\\setlength{\\topskip}{0pt}\n",
    "\\usepackage{amsmath,amssymb,amsfonts,mathtools}\n",
    "\\usepackage{xcolor}\n",
    "\\pagestyle{empty}\n",
    "\\setlength{\\parindent}{0pt}\n",
  }
  local hex = configured_hex_color(config)
  if hex ~= nil then
    parts[#parts + 1] = table.concat({
      "\\AtBeginDocument{%\n",
      ("  \\color[HTML]{%s}%%\n"):format(hex),
      ("  \\everymath\\expandafter{\\the\\everymath\\color[HTML]{%s}}%%\n"):format(hex),
      ("  \\everydisplay\\expandafter{\\the\\everydisplay\\color[HTML]{%s}}%%\n"):format(hex),
      "}\n",
    })
  end
  return table.concat(parts)
end

local macro_commands = {
  "\\newcommand",
  "\\renewcommand",
  "\\providecommand",
  "\\DeclareRobustCommand",
  "\\DeclareMathOperator",
  "\\DeclarePairedDelimiter",
}

local function balanced_macro_end(text, start_idx)
  local depth = 0
  local idx = start_idx
  local saw_arg = false
  while idx <= #text do
    local ch = text:sub(idx, idx)
    if ch == "\\" then
      idx = idx + 2
    elseif ch == "{" or ch == "[" then
      depth = depth + 1
      saw_arg = true
      idx = idx + 1
    elseif ch == "}" or ch == "]" then
      depth = math.max(0, depth - 1)
      idx = idx + 1
    elseif ch == "\n" and depth == 0 and saw_arg then
      return idx
    else
      idx = idx + 1
    end
  end
  return #text + 1
end

local function find_next_macro(text, start_idx)
  local best_start = nil
  local best_command = nil
  for _, command in ipairs(macro_commands) do
    local found = text:find(command, start_idx, true)
    if found ~= nil and (best_start == nil or found < best_start) then
      best_start = found
      best_command = command
    end
  end
  return best_start, best_command
end

local function extract_mitex_macros(text)
  text = text or ""
  local out = {}
  local idx = 1
  while idx <= #text do
    local start_idx, command = find_next_macro(text, idx)
    if start_idx == nil then
      break
    end
    local after = start_idx + #command
    local next_ch = text:sub(after, after)
    if next_ch ~= "" and next_ch:match("[%a@]") then
      idx = after
    else
      local end_idx = balanced_macro_end(text, start_idx)
      local chunk = text:sub(start_idx, end_idx - 1):gsub("%s+$", "")
      if chunk ~= "" then
        out[#out + 1] = chunk
      end
      idx = math.max(end_idx, after)
    end
  end
  return out
end

--- @param project_scope table
--- @param config table
--- @return string
function M.build_context_document(project_scope, config)
  config = config or {}
  local project_preamble = ensure_trailing_newline(project_scope and project_scope.preamble_source or "")
  local parts = {}
  if not project_preamble:find("\\documentclass", 1, false) then
    parts[#parts + 1] = "\\documentclass{article}\n"
  end
  parts[#parts + 1] = project_preamble
  parts[#parts + 1] = default_packages(config)
  if config.header ~= nil and config.header ~= "" then
    parts[#parts + 1] = ensure_trailing_newline(config.header)
  end
  return table.concat(parts)
end

--- Build the LaTeX macro prelude that is safe to pass through MiTeX.
--- Package loading and document setup stay in the full LaTeX context.
--- @param project_scope table
--- @param config table
--- @return string
function M.build_mitex_prelude(project_scope, config)
  config = config or {}
  local chunks = {}
  for _, source in ipairs({
    project_scope and project_scope.preamble_source or "",
    config.header or "",
  }) do
    for _, macro in ipairs(extract_mitex_macros(source)) do
      chunks[#chunks + 1] = macro
    end
  end
  if #chunks == 0 then
    return ""
  end
  return table.concat(chunks, "\n") .. "\n"
end

--- @param source string
--- @param backend_node_type string
--- @return string
function M.unwrap_math(source, backend_node_type)
  source = source or ""
  if backend_node_type == "math_environment" then
    return source
  end
  if backend_node_type == "inline_formula" then
    if source:sub(1, 2) == "\\(" and source:sub(-2) == "\\)" then
      return "$" .. source:sub(3, -3) .. "$"
    end
    if source:sub(1, 1) == "$" and source:sub(-1) == "$" and source:sub(1, 2) ~= "$$" then
      return source
    end
    return "$" .. source .. "$"
  end
  if backend_node_type == "displayed_equation" then
    if source:sub(1, 2) == "$$" and source:sub(-2) == "$$" then
      return "\\[" .. source:sub(3, -3) .. "\\]"
    end
    if source:sub(1, 2) == "\\[" and source:sub(-2) == "\\]" then
      return source
    end
    return "\\[" .. source .. "\\]"
  end
  return source
end

--- @param source string
--- @param backend_node_type string
--- @return string
function M.mitex_math_content(source, backend_node_type)
  source = source or ""
  if backend_node_type == "math_environment" then
    return source
  end
  if backend_node_type == "displayed_equation" then
    if source:sub(1, 2) == "$$" and source:sub(-2) == "$$" then
      return source:sub(3, -3)
    end
    if source:sub(1, 2) == "\\[" and source:sub(-2) == "\\]" then
      return source:sub(3, -3)
    end
    return source
  end
  if source:sub(1, 2) == "\\(" and source:sub(-2) == "\\)" then
    return source:sub(3, -3)
  end
  if source:sub(1, 1) == "$" and source:sub(-1) == "$" and source:sub(1, 2) ~= "$$" then
    return source:sub(2, -2)
  end
  return source
end

--- @param source string
--- @param backend_node_type string
--- @param prelude string
--- @return string
function M.build_mitex_render_text(source, backend_node_type, prelude)
  local content = (prelude or "") .. M.mitex_math_content(source, backend_node_type)
  if backend_node_type == "inline_formula" then
    return "#mi(" .. typst_string_literal(content) .. ")"
  end
  return "#mitex(" .. typst_string_literal(content) .. ")"
end

--- @param job table
--- @param context_source string
--- @return table
function M.build_formula_line_map(job, context_source)
  local source = job.source_str or job.source_text or job.str or ""
  local backend_node_type = job.backend_node_type
    or (job.semantics and job.semantics.backend_node_type)
    or "inline_formula"
  local content = M.unwrap_math(source, backend_node_type)
  local gen_start = count_lines(context_source) + 3
  local content_lines = math.max(1, count_lines(content))
  return {
    item_idx = job.item_idx,
    bufnr = job.bufnr,
    gen_start = gen_start,
    gen_end = gen_start + content_lines - 1,
    gen_start_col = 1,
    src_start = (job.range and job.range[1] or 0) + 1,
    src_end = (job.range and job.range[3] or 0) + 1,
    src_start_col = (job.range and job.range[2] or 0) + 1,
    src_end_col = (job.range and job.range[4] or 0) + 1,
  }
end

--- @param context_source string
--- @param source string
--- @param backend_node_type string
--- @return string
function M.build_formula_document(context_source, source, backend_node_type)
  return table.concat({
    ensure_trailing_newline(context_source),
    "\\begin{document}\n",
    "\\begin{preview}\n",
    ensure_trailing_newline(M.unwrap_math(source, backend_node_type)),
    "\\end{preview}\n",
    "\\end{document}\n",
  })
end

return M
