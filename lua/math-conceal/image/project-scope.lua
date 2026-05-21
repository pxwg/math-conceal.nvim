--- Shared project scope resolution for planner and compiler-service requests.

local M = {}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function get_buf_dir(bufnr)
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  if buf_file == nil or buf_file == "" then
    return vim.uv.cwd()
  end
  return vim.fn.fnamemodify(buf_file, ":h")
end

local function signature(parts)
  local normalized = {}
  for _, part in ipairs(parts or {}) do
    normalized[#normalized + 1] = tostring(part or "")
  end
  return vim.fn.sha256(table.concat(normalized, "\0"))
end

local function resolve_root_base(configured_root, cwd, project_root, buf_dir)
  return normalize(configured_root) or normalize(project_root) or normalize(buf_dir) or normalize(cwd)
end

local function effective_root_for_cache(source_root)
  local cache_root = normalize(require("math-conceal.image.workspace").base_dir())
  if source_root == nil or cache_root == nil then
    return source_root
  end
  return require("math-conceal.image.path-rewrite").common_ancestor(source_root, cache_root)
end

local function call_config_fn(fn, bufnr, buf_path, cwd, kind)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, result = pcall(fn, bufnr, buf_path, cwd, kind)
  if ok and type(result) == "string" and result ~= "" then
    return result
  end
  return nil
end

local function source_kind_for_bufnr(bufnr)
  local ok, main = pcall(require, "math-conceal.image")
  if ok and type(main.source_kind_for_bufnr) == "function" then
    return main.source_kind_for_bufnr(bufnr)
  end
  local ft = vim.bo[bufnr].filetype
  local path = vim.api.nvim_buf_get_name(bufnr) or ""
  if ft == "tex" or ft == "plaintex" or ft == "latex" or path:match("%.tex$") then
    return "latex"
  end
  return "typst"
end

local function nearest_latex_marker_root(buf_dir)
  local dir = normalize(buf_dir)
  while dir ~= nil and dir ~= "" do
    for _, marker in ipairs({ "latexmkrc", ".latexmkrc", "Tectonic.toml", ".git" }) do
      if vim.uv.fs_stat(dir .. "/" .. marker) ~= nil then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  return normalize(buf_dir)
end

local function read_file(path)
  if path == nil or path == "" then
    return ""
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return ""
  end
  return table.concat(lines, "\n")
end

local function buffer_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function preamble_before_document(text)
  text = text or ""
  local start_pos = text:find("\\begin%s*{%s*document%s*}")
  if start_pos == nil then
    return ""
  end
  return text:sub(1, start_pos - 1)
end

local function resolve_latex_scope(bufnr, kind, main, config)
  local latex_config = (config.backends and config.backends.latex) or {}
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fn.getcwd()
  local buf_dir = get_buf_dir(bufnr)

  local configured_main = normalize(call_config_fn(latex_config.get_main_file, bufnr, buf_path, cwd, kind))
  local configured_root = call_config_fn(latex_config.get_root, bufnr, buf_path, cwd, kind)
  local root_from_main = configured_main and vim.fn.fnamemodify(configured_main, ":h") or nil
  local source_root = normalize(configured_root) or normalize(root_from_main) or nearest_latex_marker_root(buf_dir)
  local effective_root = effective_root_for_cache(source_root)
  local main_path = configured_main or normalize(buf_path) or ""

  local configured_preamble = normalize(call_config_fn(latex_config.get_preamble_file, bufnr, buf_path, cwd, kind))
  local preamble_path = configured_preamble or ""
  local preamble_source = ""
  local preamble_kind = "default"
  if configured_preamble ~= nil then
    preamble_source = read_file(configured_preamble)
    preamble_kind = "file"
  elseif main_path ~= "" then
    local main_text = normalize(main_path) == normalize(buf_path) and buffer_text(bufnr) or read_file(main_path)
    preamble_source = preamble_before_document(main_text)
    preamble_kind = "main"
  end

  local compiler_args = vim.deepcopy(latex_config.compiler_args or {})
  local compiler_args_signature = signature(compiler_args)
  local preamble_signature = signature({ preamble_kind, preamble_path, preamble_source })
  local state = require("math-conceal.image.state")
  local context_signature = signature({
    "latex-context-v1",
    kind or "",
    source_root or "",
    effective_root or "",
    buf_dir or "",
    normalize(buf_path) or "",
    main_path or "",
    preamble_signature,
    compiler_args_signature,
    latex_config.compiler or "",
    latex_config.converter or "",
    latex_config.header or "",
    tostring(latex_config.mitex_fast_path ~= false),
    main._styling_prelude or "",
    tostring(state._cell_px_w or ""),
    tostring(state._cell_px_h or ""),
    tostring(state._render_ppi or config.ppi or ""),
  })

  return {
    backend_id = "latex",
    project_scope_id = context_signature,
    source_root = source_root,
    effective_root = effective_root,
    context_signature = context_signature,
    buf_dir = buf_dir,
    buf_path = buf_path,
    cwd = cwd,
    main_path = main_path,
    preamble_path = preamble_path,
    preamble_source = preamble_source,
    preamble_signature = preamble_signature,
    compiler_args = compiler_args,
    compiler_args_signature = compiler_args_signature,
  }
end

--- @param bufnr integer
--- @param kind "full"
--- @return ProjectScope
function M.resolve(bufnr, kind)
  local main = require("math-conceal.image")
  local config = main.config or {}
  local path_rewrite = require("math-conceal.image.path-rewrite")

  if source_kind_for_bufnr(bufnr) == "latex" then
    return resolve_latex_scope(bufnr, kind, main, config)
  end

  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fn.getcwd()
  local buf_dir = get_buf_dir(bufnr)
  local project_root = path_rewrite.get_project_root(buf_dir)

  local configured_root = nil
  if type(config.get_root) == "function" then
    local ok, result = pcall(config.get_root, bufnr, buf_path, cwd, kind)
    if ok and type(result) == "string" and result ~= "" then
      configured_root = result
    end
  end

  local source_root = resolve_root_base(configured_root, cwd, project_root, buf_dir)
  local effective_root = effective_root_for_cache(source_root)

  local inputs = {}
  if type(config.get_inputs) == "function" then
    local ok, result = pcall(config.get_inputs, bufnr, buf_path, cwd, kind)
    if ok and type(result) == "table" then
      inputs = result
    end
  end

  local preamble_path = ""
  if type(config.get_preamble_file) == "function" then
    local ok, result = pcall(config.get_preamble_file, bufnr, buf_path, cwd, kind)
    if ok and type(result) == "string" then
      preamble_path = normalize(result) or result
    end
  end

  local inputs_signature = signature(inputs)
  local preamble_signature = signature({ preamble_path })
  local context_signature = signature({
    kind or "",
    normalize(buf_path) or "",
    source_root or "",
    effective_root or "",
    inputs_signature,
    preamble_signature,
  })

  return {
    backend_id = "typst",
    project_scope_id = context_signature,
    source_root = source_root,
    effective_root = effective_root,
    inputs_signature = inputs_signature,
    preamble_signature = preamble_signature,
    context_signature = context_signature,
    buf_dir = buf_dir,
    buf_path = buf_path,
    cwd = cwd,
    inputs = inputs,
    preamble_path = preamble_path,
  }
end

return M
