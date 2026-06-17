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

local function resolve_preamble_include_line(bufnr, config, effective_root)
  if type(config.get_preamble_file) ~= "function" then
    return ""
  end

  local ok, path = pcall(config.get_preamble_file, bufnr, vim.api.nvim_buf_get_name(bufnr), vim.uv.cwd(), "full")
  if not ok or type(path) ~= "string" or path == "" then
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
  local preamble_include_line = resolve_preamble_include_line(bufnr, config, effective_root)

  local ctx = {
    bufnr = bufnr,
    kind = binding.kind,
    source_root = source_root,
    effective_root = effective_root,
    buf_dir = dir,
    buf_path = vim.api.nvim_buf_get_name(bufnr),
    workspace = ws,
    inputs = binding.inputs or vim.empty_dict(),
    context_units = context_units,
    preamble_include_line = preamble_include_line,
  }

  ctx.context_source = wrapper.build_context_document(config, ctx)
  ctx.context_signature = signature({
    binding.kind,
    ctx.buf_path,
    ctx.source_root,
    ctx.effective_root,
    ctx.inputs,
    ctx.context_source,
    tracker_context and tracker_context.signature or "",
    state.render_ppi(config),
  })

  if bstate.context_signature ~= ctx.context_signature then
    bstate.context_rev = (bstate.context_rev or 0) + 1
    bstate.context_signature = ctx.context_signature
  end

  ctx.context_id = signature({
    "typst",
    ctx.buf_path,
    ctx.source_root,
    ctx.effective_root,
    ctx.inputs,
    ctx.context_source,
    state.render_ppi(config),
  })
  ctx.context_rev = bstate.context_rev
  bstate.context = ctx
  return ctx
end

return M
