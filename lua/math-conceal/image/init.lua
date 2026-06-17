local M = {}

---@class MathConcealImageAttachContext
---@field bufnr integer
---@field kind string
---@field filetype string
---@field path string
---@field cwd string

---@alias MathConcealImageRootResolver fun(ctx: MathConcealImageAttachContext): string?
---@alias MathConcealImageInputsResolver fun(ctx: MathConcealImageAttachContext): table<string, string>?
---@alias MathConcealImagePathRule string|fun(ctx: MathConcealImageAttachContext): boolean

---@class MathConcealImageRenderPaths
---@field exclude MathConcealImagePathRule[]

---@class MathConcealImageRendererConfig
---@field filetypes string[]
---@field service_binary string
---@field root? string|MathConcealImageRootResolver
---@field inputs table<string, string>|MathConcealImageInputsResolver
---@field render_paths MathConcealImageRenderPaths

---@class MathConcealImageConfig
---@field enabled_by_default boolean
---@field renderers table<string, MathConcealImageRendererConfig>

---@class MathConcealImageBinding
---@field bufnr integer
---@field kind string
---@field filetype string
---@field path string
---@field enabled boolean
---@field service_binary string
---@field root string
---@field inputs table<string, string>

---@type MathConcealImageConfig
local defaults = {
  enabled_by_default = true,
  renderers = {
    typst = {
      filetypes = { "typst" },
      service_binary = "typst-concealer-service",
      root = nil,
      inputs = {},
      render_paths = {
        exclude = {},
      },
    },
  },
}

---@type MathConcealImageConfig
M.config = vim.deepcopy(defaults)

---@type table<string, string>
M._ft_to_renderer = {}

---@type table<integer, MathConcealImageBinding>
M._buffers = {}

local augroup_name = "math-conceal.image"
local augroup_id = nil

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function normalize_path(path)
  if path == nil or path == "" then
    return ""
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function valid_loaded_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

local function buffer_context(bufnr, kind)
  local path = normalize_path(vim.api.nvim_buf_get_name(bufnr))

  return {
    bufnr = bufnr,
    kind = kind,
    filetype = vim.bo[bufnr].filetype,
    path = path,
    cwd = vim.uv.cwd(),
  }
end

local function default_root(ctx)
  if ctx.path == "" then
    return ctx.cwd
  end

  local dir = vim.fs.dirname(ctx.path)
  local marker = vim.fs.find({ "typst.toml", ".git" }, { upward = true, path = dir })[1]
  if marker ~= nil then
    return vim.fs.dirname(marker)
  end
  return dir
end

local function resolve_root(spec, ctx)
  local root = nil

  if type(spec.root) == "function" then
    root = spec.root(ctx)
  elseif type(spec.root) == "string" then
    root = spec.root
  else
    root = default_root(ctx)
  end

  return normalize_path(root)
end

local function resolve_inputs(spec, ctx)
  local inputs = spec.inputs
  if type(inputs) == "function" then
    inputs = inputs(ctx)
  end

  local resolved = {}
  for key, value in pairs(inputs or {}) do
    resolved[key] = value
  end
  return resolved
end

local function build_filetype_index()
  M._ft_to_renderer = {}

  for kind, spec in pairs(M.config.renderers or {}) do
    for _, ft in ipairs(spec.filetypes or {}) do
      M._ft_to_renderer[ft] = kind
    end
  end
end

local function configured_filetypes()
  local filetypes = {}
  for ft, _ in pairs(M._ft_to_renderer) do
    filetypes[#filetypes + 1] = ft
  end
  table.sort(filetypes)
  return filetypes
end

local function path_matches_rule(rule, ctx)
  if type(rule) == "string" then
    return ctx.path:match(rule) ~= nil
  end
  if type(rule) == "function" then
    return rule(ctx) == true
  end
  return false
end

local function path_excluded(spec, ctx)
  local render_paths = spec.render_paths or {}
  for _, rule in ipairs(render_paths.exclude or {}) do
    if path_matches_rule(rule, ctx) then
      return true
    end
  end
  return false
end

local function make_binding(kind, spec, ctx)
  return {
    bufnr = ctx.bufnr,
    kind = kind,
    filetype = ctx.filetype,
    path = ctx.path,
    enabled = true,
    service_binary = spec.service_binary,
    root = resolve_root(spec, ctx),
    inputs = resolve_inputs(spec, ctx),
  }
end

local function attach_loaded_buffers()
  if not M.config.enabled_by_default then
    return
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if valid_loaded_buffer(bufnr) then
      M.attach_buf(bufnr)
    end
  end
end

---Return the renderer kind configured for a buffer's filetype.
---@param bufnr integer?
---@return string?
function M.renderer_kind_for_bufnr(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return nil
  end
  return M._ft_to_renderer[vim.bo[bufnr].filetype]
end

---Compatibility alias for the old scaffold name.
---@param bufnr integer?
---@return string?
function M.source_kind_for_bufnr(bufnr)
  return M.renderer_kind_for_bufnr(bufnr)
end

---@param bufnr integer?
---@return boolean
function M.is_supported_bufnr(bufnr)
  return M.renderer_kind_for_bufnr(bufnr) ~= nil
end

---@param bufnr integer?
---@return boolean
function M.is_render_allowed(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local kind = M.renderer_kind_for_bufnr(bufnr)
  if kind == nil then
    return false
  end

  local spec = M.config.renderers[kind]
  local ctx = buffer_context(bufnr, kind)
  return not path_excluded(spec, ctx)
end

---Attach the configured renderer binding to a buffer.
---@param bufnr integer?
---@return boolean
function M.attach_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local kind = M.renderer_kind_for_bufnr(bufnr)
  if kind == nil then
    M._buffers[bufnr] = nil
    return false
  end

  local spec = M.config.renderers[kind]
  local ctx = buffer_context(bufnr, kind)
  if path_excluded(spec, ctx) then
    M._buffers[bufnr] = nil
    return false
  end

  M._buffers[bufnr] = make_binding(kind, spec, ctx)
  return true
end

---@param bufnr integer?
---@return table?
function M.get_binding(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return M._buffers[bufnr]
end

---@param bufnr integer?
---@return boolean
function M.enable_buf(bufnr)
  return M.attach_buf(bufnr)
end

---@param bufnr integer?
function M.disable_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  M._buffers[bufnr] = nil
end

---@param bufnr integer?
---@return boolean
function M.toggle_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if M._buffers[bufnr] ~= nil then
    M.disable_buf(bufnr)
    return false
  end
  return M.enable_buf(bufnr)
end

---Refresh the buffer binding. Concrete renderers will later hook in here.
---@param bufnr integer?
---@return boolean
function M.rerender_buf(bufnr)
  return M.attach_buf(bufnr)
end

---Set up renderer registration and buffer attachment.
---@param cfg table?
function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), cfg or {})
  M._buffers = {}
  build_filetype_index()

  augroup_id = vim.api.nvim_create_augroup(augroup_name, { clear = true })

  local fts = configured_filetypes()
  if #fts > 0 then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup_id,
      pattern = fts,
      desc = "attach math-conceal image renderer bindings",
      callback = function(ev)
        if M.config.enabled_by_default then
          M.attach_buf(ev.buf)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup_id,
    desc = "clear math-conceal image renderer binding",
    callback = function(ev)
      M._buffers[ev.buf] = nil
    end,
  })

  attach_loaded_buffers()
end

return M
