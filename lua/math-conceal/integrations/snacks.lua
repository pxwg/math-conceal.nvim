local M = {}

local defaults = {
  enabled = true,
  unicode = true,
  image = true,
  mode = "presentation",
}

M.config = vim.deepcopy(defaults)

local states = setmetatable({}, { __mode = "k" })
local wrapped_functions = setmetatable({}, { __mode = "k" })
local installation
local retry_group = vim.api.nvim_create_augroup("math-conceal.integrations.snacks", { clear = true })
local retry_installed = false

local function pack(...)
  return { n = select("#", ...), ... }
end

local function context_key(ctx)
  return ctx.picker or ctx.preview
end

local function valid_loaded_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

local function current_preview_buf(ctx)
  local ok, bufnr = pcall(function()
    return ctx.buf
  end)
  if ok and valid_loaded_buffer(bufnr) then
    return bufnr
  end
  local win = ctx.preview and ctx.preview.win or nil
  return win and valid_loaded_buffer(win.buf) and win.buf or nil
end

local function normalize_path(path, ctx)
  if path == nil or path == "" then
    return ""
  end
  path = tostring(path)
  local absolute = path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil
  if not absolute then
    local item = ctx.item or {}
    local picker_opts = ctx.picker and ctx.picker.opts or {}
    local cwd = item.cwd or picker_opts.cwd or vim.uv.cwd()
    path = vim.fs.joinpath(cwd, path)
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function item_path(ctx)
  local item = ctx.item or {}
  if valid_loaded_buffer(item.buf) then
    local name = vim.api.nvim_buf_get_name(item.buf)
    if name ~= "" then
      return normalize_path(name, ctx)
    end
  end
  local snacks = rawget(_G, "Snacks") or package.loaded.snacks
  if snacks and snacks.picker and snacks.picker.util and type(snacks.picker.util.path) == "function" then
    local ok, path = pcall(snacks.picker.util.path, item)
    if ok and path ~= nil then
      return normalize_path(path, ctx)
    end
  end
  if item.file ~= nil then
    return normalize_path(item.file, ctx)
  end
  return ""
end

local function item_key(ctx, path)
  local item = ctx.item or {}
  if valid_loaded_buffer(item.buf) then
    return "buf:" .. tostring(item.buf)
  end
  return path ~= "" and "path:" .. path or nil
end

local function preview_filetype(ctx, bufnr, path, opts)
  if type(opts.filetype) == "function" then
    return opts.filetype(ctx, bufnr, path)
  elseif type(opts.filetype) == "string" then
    return opts.filetype
  end

  local picker_opts = ctx.picker and ctx.picker.opts or {}
  local configured = picker_opts.previewers and picker_opts.previewers.file and picker_opts.previewers.file.ft or nil
  if configured ~= nil and configured ~= "bigfile" then
    return configured
  end

  local item = ctx.item or {}
  if valid_loaded_buffer(item.buf) then
    local filetype = vim.bo[item.buf].filetype
    if filetype ~= "" and not filetype:find("snacks_picker_preview", 1, true) then
      return filetype
    end
  end

  if path ~= "" then
    local ok, detected = pcall(vim.filetype.match, { filename = path, buf = bufnr })
    if ok and detected ~= "bigfile" then
      return detected
    end
  end
end

local function merged_opts(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.config), opts or {})
end

local function state_for(ctx)
  local key = context_key(ctx)
  if key == nil then
    return nil
  end
  local state = states[key]
  if state == nil then
    state = {
      key = key,
      owner = {},
    }
    states[key] = state
  end
  return state
end

local function cleanup_state(state)
  if state == nil then
    return false
  end
  local detached = false
  if state.attachment ~= nil then
    detached = state.attachment:detach()
  end
  state.attachment = nil
  state.bufnr = nil
  state.item_key = nil
  state.changedtick = nil
  return detached
end

local function ensure_close_hook(ctx, state)
  local picker = ctx.picker
  if picker == nil or state.close_hook == true then
    return
  end
  state.close_hook = true
  picker.opts = picker.opts or {}
  local previous = picker.opts.on_close
  picker.opts.on_close = function(...)
    cleanup_state(state)
    states[state.key] = nil
    if previous ~= nil then
      return previous(...)
    end
  end
end

local function default_source(ctx, bufnr, opts)
  local path = item_path(ctx)
  local source = {
    path = path,
    filetype = preview_filetype(ctx, bufnr, path, opts),
  }

  if type(opts.source) == "function" then
    return opts.source(ctx, bufnr, vim.deepcopy(source))
  elseif type(opts.source) == "string" then
    source.kind = opts.source
  elseif type(opts.source) == "table" then
    source = vim.tbl_extend("force", source, opts.source)
  elseif opts.source == false then
    return nil
  end
  return source
end

local function scratch_preview(ctx, bufnr)
  local item = ctx.item or {}
  return not (valid_loaded_buffer(item.buf) and item.buf == bufnr)
end

local function requested_surfaces(opts)
  local surfaces = vim.deepcopy(opts.surfaces or {})
  if surfaces.unicode == nil then
    surfaces.unicode = opts.unicode ~= false
  end
  if surfaces.image == nil then
    surfaces.image = opts.image ~= false
  end
  return surfaces
end

---Resolve the source descriptor for a rendered Snacks preview context.
---@param ctx snacks.picker.preview.ctx
---@param opts table?
---@return table?, integer?, string?
function M.resolve(ctx, opts)
  opts = merged_opts(opts)
  local bufnr = current_preview_buf(ctx)
  if bufnr == nil then
    return nil
  end
  local candidate = default_source(ctx, bufnr, opts)
  if candidate == nil then
    return nil, bufnr
  end
  local source = require("math-conceal").resolve_source(bufnr, candidate)
  return source, bufnr, item_key(ctx, source and source.path or item_path(ctx))
end

---Attach conceal to a Snacks preview after the previewer has committed its content.
---@param ctx snacks.picker.preview.ctx
---@param opts table?
---@return table?
function M.sync(ctx, opts)
  opts = merged_opts(opts)
  if opts.enabled == false then
    M.detach(ctx)
    return nil
  end

  local source, bufnr, key = M.resolve(ctx, opts)
  local state = state_for(ctx)
  if state == nil then
    return nil
  end
  ensure_close_hook(ctx, state)

  if source == nil or bufnr == nil or key == nil then
    cleanup_state(state)
    return nil
  end
  if state.attachment ~= nil and (state.bufnr ~= bufnr or state.item_key ~= key) then
    cleanup_state(state)
  end

  local mode = scratch_preview(ctx, bufnr) and opts.mode or nil
  if mode == false then
    mode = nil
  end
  local ok, attachment = pcall(require("math-conceal").attach, bufnr, {
    source = source,
    surfaces = requested_surfaces(opts),
    mode = mode,
    owner = state.owner,
  })
  if not ok then
    cleanup_state(state)
    vim.notify_once("math-conceal Snacks preview attach failed: " .. tostring(attachment), vim.log.levels.WARN)
    return nil
  end

  state.attachment = attachment
  state.bufnr = bufnr
  state.item_key = key
  state.changedtick = vim.b[bufnr].changedtick
  return attachment
end

---Detach the attachment owned by a Snacks picker or preview context.
---@param target table
---@return boolean
function M.detach(target)
  local key = target and (target.picker or target.preview or target) or nil
  local state = key and states[key] or nil
  if state == nil then
    return false
  end
  local detached = cleanup_state(state)
  states[key] = nil
  return detached
end

local function prepare(ctx)
  local state = state_for(ctx)
  if state == nil then
    return nil
  end
  ensure_close_hook(ctx, state)
  if state.attachment == nil then
    return state
  end

  local bufnr = current_preview_buf(ctx)
  local path = item_path(ctx)
  local key = item_key(ctx, path)
  local changed = valid_loaded_buffer(state.bufnr) and vim.b[state.bufnr].changedtick ~= state.changedtick
  if not state.attachment:is_current() or state.bufnr ~= bufnr or state.item_key ~= key or changed then
    cleanup_state(state)
  end
  return state
end

---Wrap a synchronous Snacks previewer with source-aware conceal attachment.
---@param previewer function
---@param opts table?
---@return function
function M.wrap(previewer, opts)
  assert(type(previewer) == "function", "math-conceal Snacks previewer must be a function")
  local wrapped = wrapped_functions[previewer]
  if wrapped ~= nil then
    previewer = wrapped.previewer
  end

  local wrapper = function(ctx)
    local state = prepare(ctx)
    local before_buf = state and state.bufnr or nil
    local before_tick = state and state.changedtick or nil
    local result = pack(pcall(previewer, ctx))
    if not result[1] then
      if state ~= nil then
        cleanup_state(state)
      end
      error(result[2], 0)
    end

    if result.n >= 2 and result[2] == false then
      if state ~= nil then
        cleanup_state(state)
      end
      return unpack(result, 2, result.n)
    end

    if
      state ~= nil
      and state.attachment ~= nil
      and state.bufnr == before_buf
      and state.changedtick == before_tick
      and valid_loaded_buffer(state.bufnr)
      and vim.b[state.bufnr].changedtick ~= before_tick
    then
      state.attachment:refresh({ unicode = true, image = true })
    end
    M.sync(ctx, opts)
    return unpack(result, 2, result.n)
  end
  wrapped_functions[wrapper] = { previewer = previewer, opts = opts }
  return wrapper
end

local function clear_retry()
  vim.api.nvim_clear_autocmds({ group = retry_group })
  retry_installed = false
end

local function install_retry()
  if retry_installed then
    return
  end
  retry_installed = true
  vim.api.nvim_create_autocmd("User", {
    group = retry_group,
    pattern = { "LazyLoad", "VeryLazy" },
    callback = function()
      vim.schedule(function()
        M.setup(M.config)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = retry_group,
    once = true,
    callback = function()
      vim.schedule(function()
        M.setup(M.config)
      end)
    end,
  })
end

---Install the default adapter around Snacks' stock file previewer.
---@param opts table?
---@return boolean
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if M.config.enabled == false then
    M.teardown()
    return false
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" then
    install_retry()
    return false
  end
  local ok_previewers, previewers = pcall(function()
    return snacks.picker and snacks.picker.preview or nil
  end)
  if not ok_previewers or type(previewers) ~= "table" or type(previewers.file) ~= "function" then
    install_retry()
    return false
  end

  if installation ~= nil and installation.previewers == previewers and previewers.file == installation.wrapper then
    clear_retry()
    return true
  end
  if installation ~= nil then
    M.teardown()
  end

  local original = previewers.file
  local wrapper = M.wrap(original)
  previewers.file = wrapper
  installation = {
    previewers = previewers,
    original = original,
    wrapper = wrapper,
  }
  clear_retry()
  return true
end

---Remove the default Snacks patch and all adapter-owned attachments.
function M.teardown()
  for key, state in pairs(states) do
    cleanup_state(state)
    states[key] = nil
  end
  if installation ~= nil and installation.previewers.file == installation.wrapper then
    installation.previewers.file = installation.original
  end
  installation = nil
  clear_retry()
end

return M
