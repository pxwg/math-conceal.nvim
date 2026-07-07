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

local function resolve_preamble_file(bufnr, binding)
  local preamble_file = binding and binding.preamble_file or nil
  if type(preamble_file) == "function" then
    local ok, path = pcall(preamble_file, {
      bufnr = bufnr,
      kind = binding.kind,
      source_kind = binding.source_kind,
      filetype = binding.filetype,
      path = vim.api.nvim_buf_get_name(bufnr),
      cwd = vim.uv.cwd(),
    })
    if ok and type(path) == "string" and path ~= "" then
      return path
    end
    return nil
  end
  if type(preamble_file) == "string" and preamble_file ~= "" then
    return preamble_file
  end
  return nil
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
    state.render_ppi(config),
  })
  ctx.context_rev = bstate.context_rev
  bstate.context = ctx
  return ctx
end

return M
