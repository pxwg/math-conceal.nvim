local path_rewrite = require("math-conceal.image.path-rewrite")
local state = require("math-conceal.image.state")
local workspace = require("math-conceal.image.workspace")
local wrapper = require("math-conceal.image.wrapper")

local M = {}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function buf_dir(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == nil or name == "" then
    return vim.uv.cwd()
  end
  return vim.fn.fnamemodify(name, ":h")
end

local function signature(parts)
  local normalized = {}
  for _, part in ipairs(parts or {}) do
    if type(part) == "table" then
      local keys = vim.tbl_keys(part)
      table.sort(keys)
      for _, key in ipairs(keys) do
        normalized[#normalized + 1] = tostring(key) .. "=" .. tostring(part[key])
      end
    else
      normalized[#normalized + 1] = tostring(part or "")
    end
  end
  return vim.fn.sha256(table.concat(normalized, "\0"))
end

local function resolver_context(bufnr, binding)
  return {
    bufnr = bufnr,
    kind = binding.kind,
    source_kind = binding.source_kind,
    filetype = binding.filetype,
    path = binding.path or vim.api.nvim_buf_get_name(bufnr),
    cwd = binding.cwd or vim.uv.cwd(),
  }
end

local function resolve_string_option(bufnr, binding, value)
  if type(value) == "function" then
    local ok, resolved = pcall(value, resolver_context(bufnr, binding))
    if ok and type(resolved) == "string" and resolved ~= "" then
      return resolved
    end
    return nil
  end
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

local function resolve_preamble_file(bufnr, binding)
  return resolve_string_option(bufnr, binding, binding and binding.preamble_file or nil)
end

local function read_text_file(path)
  local file, err = io.open(path, "rb")
  if file == nil then
    return nil, err
  end
  local ok, content = pcall(file.read, file, "*a")
  file:close()
  if not ok then
    return nil, content
  end
  return content
end

local function resolve_mitex_preamble(bufnr, binding, bstate)
  local cached = bstate.mitex_preamble_cache
  if cached ~= nil then
    return cached.content, cached.path
  end

  local parts = {}
  local path = resolve_string_option(bufnr, binding, binding and binding.mitex_preamble_file or nil)
  local abs = normalize(path)
  if abs ~= nil then
    local content, err = read_text_file(abs)
    if content ~= nil and content ~= "" then
      parts[#parts + 1] = content
    elseif content == nil then
      vim.schedule(function()
        vim.notify_once(
          string.format("[math-conceal.image] failed to read MiTeX preamble '%s': %s", abs, tostring(err)),
          vim.log.levels.ERROR
        )
      end)
    end
  end

  local inline = binding and binding.mitex_preamble or nil
  if type(inline) == "string" and inline ~= "" then
    parts[#parts + 1] = inline
  end

  local combined = ""
  for _, part in ipairs(parts) do
    if combined ~= "" and combined:sub(-1) ~= "\n" and part:sub(1, 1) ~= "\n" then
      combined = combined .. "\n"
    end
    combined = combined .. part
  end
  combined = combined:gsub("\r\n", "\n"):gsub("\r", "\n")
  bstate.mitex_preamble_cache = { content = combined, path = abs }
  return combined, abs
end

function M.invalidate_mitex_preamble(bufnr)
  state.get_buf_state(bufnr).mitex_preamble_cache = nil
end

local function resolve_preamble_include_line(bufnr, binding, effective_root)
  local path = resolve_preamble_file(bufnr, binding)
  if type(path) ~= "string" or path == "" then
    return ""
  end

  local abs = normalize(path)
  if abs == nil then
    return ""
  end
  return '#include "' .. path_rewrite.encode_root_relative(abs, effective_root) .. '"\n'
end

function M.resolve(bufnr, binding, tracker_context, config)
  local bstate = state.get_buf_state(bufnr)
  local dir = buf_dir(bufnr)
  local source_root = normalize(binding.root)
    or path_rewrite.get_project_root(dir)
    or normalize(dir)
    or normalize(vim.uv.cwd())
  local ws = workspace.for_buffer(bufnr)
  local effective_root = path_rewrite.common_ancestor(source_root, ws.root)
  local context_units = vim.deepcopy((tracker_context and tracker_context.units) or {})
  local mitex_preamble, mitex_preamble_path = resolve_mitex_preamble(bufnr, binding, bstate)

  local ctx = {
    bufnr = bufnr,
    kind = binding.kind,
    source_root = source_root,
    effective_root = effective_root,
    buf_dir = dir,
    buf_path = vim.api.nvim_buf_get_name(bufnr),
    workspace = ws,
    inputs = binding.inputs or vim.empty_dict(),
    backend = binding.backend or "typst",
    wrapper = binding.wrapper or binding.kind,
    renderer = binding.kind,
    source_kind = binding.source_kind or binding.kind,
    header = binding.header or "",
    mitex_package = binding.mitex_package,
    mitex_preamble = mitex_preamble,
    mitex_preamble_path = mitex_preamble_path,
    code_block = vim.deepcopy(binding.code_block or {}),
    context_units = context_units,
    preamble_include_line = resolve_preamble_include_line(bufnr, binding, effective_root),
  }

  ctx.context_source = wrapper.build_context_document(config, ctx)
  ctx.flow_context_source = wrapper.build_flow_context_document(ctx)
  ctx.context_signature = signature({
    binding.kind,
    binding.source_kind,
    binding.backend,
    binding.wrapper,
    ctx.buf_path,
    ctx.source_root,
    ctx.effective_root,
    ctx.inputs,
    ctx.context_source,
    ctx.flow_context_source,
    ctx.mitex_package or "",
    ctx.mitex_preamble_path or "",
    ctx.mitex_preamble or "",
    tracker_context and tracker_context.signature or "",
    state.render_ppi(config),
  })

  if bstate.context_signature ~= ctx.context_signature then
    bstate.context_rev = (bstate.context_rev or 0) + 1
    bstate.context_signature = ctx.context_signature
  end

  ctx.context_id = signature({
    ctx.backend or "typst",
    ctx.wrapper or "",
    ctx.buf_path,
    ctx.source_root,
    ctx.effective_root,
    ctx.inputs,
    ctx.context_source,
    ctx.mitex_package or "",
    ctx.mitex_preamble_path or "",
    ctx.mitex_preamble or "",
    state.render_ppi(config),
  })
  ctx.context_rev = bstate.context_rev
  bstate.context = ctx
  return ctx
end

return M
