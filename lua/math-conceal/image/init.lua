local projection = require("math-conceal.image.projection")
local state = require("math-conceal.image.state")
local tracker = require("math-conceal.image.tracker")
local window_options = require("math-conceal.window-options")

local M = {}

---@class MathConcealImageAttachContext
---@field bufnr integer
---@field kind string
---@field filetype string
---@field path string
---@field cwd string

---@alias MathConcealImageRootResolver fun(ctx: MathConcealImageAttachContext): string?
---@alias MathConcealImageInputsResolver fun(ctx: MathConcealImageAttachContext): table|string[]?
---@alias MathConcealImagePathRule string|fun(ctx: MathConcealImageAttachContext): boolean

---@class MathConcealImageRendererConfig
---@field filetypes string[]
---@field service_binary string
---@field live_debounce integer
---@field source_kind string?
---@field scanner string?
---@field backend string?
---@field wrapper string?
---@field root? string|MathConcealImageRootResolver
---@field inputs table<string, string>|string[]|MathConcealImageInputsResolver
---@field header string?
---@field preamble_file string|function?
---@field mitex_package string?
---@field code_render { allow?: string[]|table<string, boolean> }?
---@field code_block { padding_cols?: integer, right_padding_cols?: integer, margin_pt?: number, min_cols?: integer }?
---@field render_paths table

---@class MathConcealImageConfig
---@field enabled_by_default boolean
---@field tracker table
---@field renderers table<string, MathConcealImageRendererConfig>
---@field styling_type "colorscheme"|"simple"|"none"
---@field color string?
---@field ppi integer
---@field math_baseline_pt number
---@field formula_worker_count integer
---@field do_diagnostics boolean
---@field conceal_in_normal boolean
---@field live_preview_enabled boolean
---@field preview_idle_timeout_ms integer
---@field hidden_service_idle_ms integer
---@field block_padding_cols integer

local defaults = {
  enabled_by_default = true,
  tracker = {
    debug = false,
  },
  styling_type = "colorscheme",
  color = nil,
  ppi = 300,
  math_baseline_pt = 11,
  formula_worker_count = 2,
  do_diagnostics = true,
  conceal_in_normal = false,
  live_preview_enabled = true,
  preview_idle_timeout_ms = 1000,
  hidden_service_idle_ms = 2000,
  block_padding_cols = 0,
  renderers = {
    typst = {
      filetypes = { "typst" },
      service_binary = "typst-concealer-service",
      live_debounce = 0,
      source_kind = "typst",
      scanner = "typst",
      backend = "typst",
      wrapper = "typst",
      root = nil,
      inputs = {},
      header = "",
      preamble_file = nil,
      code_render = {
        allow = {},
      },
      code_block = {
        padding_cols = 0,
        right_padding_cols = 1,
        margin_pt = 0,
        min_cols = 8,
      },
      render_paths = {
        exclude = {},
      },
    },
    markdown = {
      filetypes = { "markdown" },
      service_binary = "typst-concealer-service",
      live_debounce = 0,
      source_kind = "markdown",
      scanner = "markdown",
      backend = "typst",
      wrapper = "mitex",
      root = nil,
      inputs = {},
      header = "",
      preamble_file = nil,
      mitex_package = "@preview/mitex:0.2.7",
      render_paths = {
        exclude = {},
      },
    },
  },
}

M.config = vim.deepcopy(defaults)
M._ft_to_renderer = {}
M._buffers = {}

local augroup_name = "math-conceal.image"
local augroup_id = nil
local cursor_sync_pending = {}
local cursor_sync_generation = {}
local resume_on_read = {}
local hidden_service_timers = {}

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

local function default_root(ctx)
  if ctx.path == "" then
    return ctx.cwd
  end
  local dir = vim.fs.dirname(ctx.path)
  local marker = vim.fs.find({ "typst.toml", ".git", ".jj", ".hg" }, { upward = true, path = dir })[1]
  if marker ~= nil then
    return vim.fs.dirname(marker)
  end
  return dir
end

local function buffer_context(bufnr, kind)
  return {
    bufnr = bufnr,
    kind = kind,
    filetype = vim.bo[bufnr].filetype,
    path = normalize_path(vim.api.nvim_buf_get_name(bufnr)),
    cwd = vim.uv.cwd(),
  }
end

local function parse_input_list(values, out)
  for _, value in ipairs(values or {}) do
    local key, val = tostring(value):match("^([^=]+)=(.*)$")
    if key ~= nil then
      out[key] = val
    end
  end
end

local function resolve_inputs(spec, ctx)
  local inputs = spec.inputs
  if type(inputs) == "function" then
    inputs = inputs(ctx)
  end

  local resolved = {}
  if vim.islist(inputs or {}) then
    parse_input_list(inputs, resolved)
  else
    for key, value in pairs(inputs or {}) do
      resolved[key] = value
    end
  end

  if next(resolved) == nil then
    return vim.empty_dict()
  end
  return resolved
end

local function resolve_root(spec, ctx)
  local root
  if type(spec.root) == "function" then
    root = spec.root(ctx)
  elseif type(spec.root) == "string" then
    root = spec.root
  else
    root = default_root(ctx)
  end
  return normalize_path(root)
end

local function setup_prelude()
  if M.config.styling_type == "colorscheme" then
    local color = M.config.color
    if color == nil then
      local hl = vim.api.nvim_get_hl(0, { name = "Normal" })
      color = string.format('rgb("#%06X")', hl.fg or 0xFFFFFF)
    end
    M.config._styling_prelude = ""
      .. "#set page(width: auto, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n"
      .. "#set text("
      .. color
      .. ', top-edge: "ascender", bottom-edge: "descender")\n'
      .. "#set line(stroke: "
      .. color
      .. ")\n"
      .. "#set table(stroke: "
      .. color
      .. ")\n"
      .. "#set circle(stroke: "
      .. color
      .. ")\n"
      .. "#set ellipse(stroke: "
      .. color
      .. ")\n"
      .. "#set curve(stroke: "
      .. color
      .. ")\n"
      .. "#set polygon(stroke: "
      .. color
      .. ")\n"
      .. "#set rect(stroke: "
      .. color
      .. ")\n"
      .. "#set square(stroke: "
      .. color
      .. ")\n"
  elseif M.config.styling_type == "simple" then
    M.config._styling_prelude = ""
      .. "#set page(width: auto, height: auto, margin: 0.75pt, fill: none)\n"
      .. '#set text(top-edge: "ascender", bottom-edge: "descender")\n'
  else
    M.config._styling_prelude = ""
  end
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
  local fts = vim.tbl_keys(M._ft_to_renderer)
  table.sort(fts)
  return fts
end

local function path_matches_rule(rule, ctx)
  if type(rule) == "string" then
    return ctx.path:match(rule) ~= nil
  end
  if type(rule) == "function" then
    local ok, result = pcall(rule, ctx)
    return ok and result == true
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
  local source_kind = spec.source_kind or spec.scanner or kind
  return {
    bufnr = ctx.bufnr,
    kind = kind,
    source_kind = source_kind,
    scanner = spec.scanner or source_kind,
    backend = spec.backend or "typst",
    wrapper = spec.wrapper or kind,
    filetype = ctx.filetype,
    path = ctx.path,
    enabled = true,
    service_binary = spec.service_binary,
    live_debounce = tonumber(spec.live_debounce) or 0,
    root = resolve_root(spec, ctx),
    inputs = resolve_inputs(spec, ctx),
    header = spec.header or "",
    preamble_file = spec.preamble_file,
    mitex_package = spec.mitex_package,
    code_block = vim.deepcopy(spec.code_block or {}),
  }
end

local function tracker_debug_enabled()
  return type(M.config.tracker) == "table" and M.config.tracker.debug == true
end

local function attached_bufnrs()
  local bufs = vim.tbl_keys(M._buffers)
  table.sort(bufs)
  return bufs
end

local function close_hidden_service_timer(bufnr)
  local timer = hidden_service_timers[bufnr]
  if timer == nil then
    return
  end
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
  hidden_service_timers[bufnr] = nil
end

local function close_all_hidden_service_timers()
  for bufnr in pairs(hidden_service_timers) do
    close_hidden_service_timer(bufnr)
  end
end

local function buffer_visible(bufnr)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return true
    end
  end
  return false
end

local function hidden_service_idle_ms()
  local timeout = tonumber(M.config.hidden_service_idle_ms)
  if timeout == nil then
    timeout = 2000
  end
  return timeout
end

local function stop_hidden_services(bufnr)
  hidden_service_timers[bufnr] = nil
  if M._buffers[bufnr] == nil or buffer_visible(bufnr) then
    return
  end

  local session = require("math-conceal.image.session")
  local ok_preview, preview = pcall(require, "math-conceal.image.preview")
  if ok_preview and type(preview.clear) == "function" then
    pcall(preview.clear, bufnr, { skip_idle_stop = true })
  end
  session.stop(bufnr, "preview")
  if not session.stop_if_idle(bufnr, "full") then
    -- Full renders own projection pending state.  Do not cancel them from the
    -- hidden-buffer path; try again after the same idle interval.
    M._schedule_hidden_service_stop(bufnr)
  end
end

function M._schedule_hidden_service_stop(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if M._buffers[bufnr] == nil or buffer_visible(bufnr) then
    close_hidden_service_timer(bufnr)
    return
  end

  local timeout = hidden_service_idle_ms()
  if timeout < 0 then
    close_hidden_service_timer(bufnr)
    return
  end
  if hidden_service_timers[bufnr] ~= nil then
    return
  end

  local timer = vim.uv.new_timer()
  hidden_service_timers[bufnr] = timer
  timer:start(
    math.max(0, timeout),
    0,
    vim.schedule_wrap(function()
      if not timer:is_closing() then
        timer:close()
      end
      stop_hidden_services(bufnr)
    end)
  )
end

function M.renderer_kind_for_bufnr(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not valid_loaded_buffer(bufnr) then
    return nil
  end
  return M._ft_to_renderer[vim.bo[bufnr].filetype]
end

function M.source_kind_for_bufnr(bufnr)
  local kind = M.renderer_kind_for_bufnr(bufnr)
  local spec = kind and M.config.renderers[kind] or nil
  return spec and (spec.source_kind or spec.scanner or kind) or nil
end

function M.is_supported_bufnr(bufnr)
  return M.renderer_kind_for_bufnr(bufnr) ~= nil
end

function M.is_render_allowed(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local kind = M.renderer_kind_for_bufnr(bufnr)
  if kind == nil then
    return false
  end
  local spec = M.config.renderers[kind]
  return not path_excluded(spec, buffer_context(bufnr, kind))
end

function M.attach_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local keep_resume = resume_on_read[bufnr] == true
  local kind = M.renderer_kind_for_bufnr(bufnr)
  if kind == nil then
    M.disable_buf(bufnr, { keep_resume = keep_resume })
    return false
  end

  local spec = M.config.renderers[kind]
  local ctx = buffer_context(bufnr, kind)
  if path_excluded(spec, ctx) then
    M.disable_buf(bufnr, { keep_resume = keep_resume })
    return false
  end

  local binding = make_binding(kind, spec, ctx)
  close_hidden_service_timer(bufnr)
  M._buffers[bufnr] = binding
  resume_on_read[bufnr] = nil
  window_options.attach(bufnr, "image")
  tracker.attach(bufnr, {
    kind = binding.scanner or binding.source_kind or kind,
    debug = tracker_debug_enabled(),
    on_repair = projection.on_tracker_repair,
  })
  return true
end

function M.get_binding(bufnr)
  return M._buffers[normalize_bufnr(bufnr)]
end

function M.enable_buf(bufnr)
  return M.attach_buf(bufnr)
end

function M.disable_buf(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  cursor_sync_pending[bufnr] = nil
  cursor_sync_generation[bufnr] = (cursor_sync_generation[bufnr] or 0) + 1
  if opts.keep_resume ~= true then
    resume_on_read[bufnr] = nil
  end
  close_hidden_service_timer(bufnr)
  M._buffers[bufnr] = nil
  window_options.detach(bufnr, "image")
  projection.detach(bufnr)
  tracker.detach(bufnr)
end

function M.toggle_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if M._buffers[bufnr] ~= nil then
    M.disable_buf(bufnr)
    return false
  end
  return M.enable_buf(bufnr)
end

function M.rerender_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if M._buffers[bufnr] == nil then
    return M.attach_buf(bufnr)
  end
  projection.force_render(bufnr)
  return true
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

local function detach_all()
  for _, bufnr in ipairs(attached_bufnrs()) do
    M.disable_buf(bufnr)
  end
end

local function sync_cursor_now(bufnr)
  if M._buffers[bufnr] == nil then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  tracker.sync_cursor_nested(bufnr, {
    enabled = not (M.config.conceal_in_normal == true and mode == "n"),
  })
  projection.sync_cursor(bufnr, { preview_immediate = true })
end

local function schedule_cursor_sync(bufnr)
  if cursor_sync_pending[bufnr] == true then
    return
  end
  cursor_sync_pending[bufnr] = true
  local generation = (cursor_sync_generation[bufnr] or 0) + 1
  cursor_sync_generation[bufnr] = generation
  vim.schedule(function()
    if cursor_sync_generation[bufnr] ~= generation then
      return
    end
    cursor_sync_pending[bufnr] = nil
    if valid_loaded_buffer(bufnr) then
      sync_cursor_now(bufnr)
    end
  end)
end

local function setup_autocmds()
  augroup_id = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  local fts = configured_filetypes()
  if #fts > 0 then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup_id,
      pattern = fts,
      desc = "attach math-conceal image renderer",
      callback = function(ev)
        if M.config.enabled_by_default or resume_on_read[ev.buf] == true then
          M.attach_buf(ev.buf)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup_id,
    desc = "reattach math-conceal image renderer after reload",
    callback = function(ev)
      if
        valid_loaded_buffer(ev.buf)
        and (M._buffers[ev.buf] ~= nil or M.config.enabled_by_default or resume_on_read[ev.buf] == true)
      then
        M.attach_buf(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufUnload", {
    group = augroup_id,
    desc = "detach math-conceal image renderer while preserving manual reload intent",
    callback = function(ev)
      if M._buffers[ev.buf] == nil and resume_on_read[ev.buf] ~= true then
        return
      end
      local should_resume = M.config.enabled_by_default ~= true
      M.disable_buf(ev.buf, { keep_resume = should_resume })
      if should_resume then
        resume_on_read[ev.buf] = true
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup_id,
    desc = "clear math-conceal image renderer",
    callback = function(ev)
      resume_on_read[ev.buf] = nil
      M.disable_buf(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = augroup_id,
    desc = "sync math-conceal image cursor preview",
    callback = function(ev)
      if M._buffers[ev.buf] ~= nil then
        if ev.event == "ModeChanged" then
          cursor_sync_pending[ev.buf] = nil
          cursor_sync_generation[ev.buf] = (cursor_sync_generation[ev.buf] or 0) + 1
          sync_cursor_now(ev.buf)
        else
          schedule_cursor_sync(ev.buf)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup_id,
    desc = "refresh math-conceal image display geometry",
    callback = function()
      local seen = {}
      for _, winid in ipairs(vim.v.event.windows or {}) do
        if vim.api.nvim_win_is_valid(winid) then
          local bufnr = vim.api.nvim_win_get_buf(winid)
          if M._buffers[bufnr] ~= nil and not seen[bufnr] then
            seen[bufnr] = true
            projection.on_layout_change(bufnr)
          end
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup_id,
    desc = "refresh math-conceal image display strategy for new windows",
    callback = function(ev)
      close_hidden_service_timer(ev.buf)
      if M._buffers[ev.buf] ~= nil then
        projection.on_layout_change(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabLeave", {
    group = augroup_id,
    desc = "release inactive math-conceal image placements",
    callback = function()
      projection.close_tab(vim.api.nvim_get_current_tabpage())
    end,
  })

  vim.api.nvim_create_autocmd("TabEnter", {
    group = augroup_id,
    desc = "restore active math-conceal image placements",
    callback = function()
      for _, bufnr in ipairs(attached_bufnrs()) do
        if buffer_visible(bufnr) then
          close_hidden_service_timer(bufnr)
        end
        projection.on_layout_change(bufnr)
        M._schedule_hidden_service_stop(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup_id,
    desc = "release closed math-conceal image window placement",
    callback = function(ev)
      local winid = tonumber(ev.match)
      if winid ~= nil then
        projection.close_window(winid)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufHidden", "BufWinLeave" }, {
    group = augroup_id,
    desc = "stop idle math-conceal services for hidden buffers",
    callback = function(ev)
      local bufnr = ev.buf
      vim.schedule(function()
        if valid_loaded_buffer(bufnr) then
          if M._buffers[bufnr] ~= nil then
            projection.on_layout_change(bufnr)
          end
          M._schedule_hidden_service_stop(bufnr)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = augroup_id,
    pattern = { "wrap", "number", "relativenumber", "signcolumn" },
    desc = "refresh math-conceal image display strategy after window option changes",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if M._buffers[bufnr] ~= nil then
        projection.on_layout_change(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup_id,
    desc = "rerender math-conceal images when terminal cell metrics change",
    callback = function()
      local changed = state.refresh_cell_px_size(M.config)
      for _, bufnr in ipairs(attached_bufnrs()) do
        if changed then
          projection.force_render(bufnr)
        else
          projection.on_layout_change(bufnr)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup_id,
    desc = "rerender math-conceal images after colorscheme changes",
    callback = function()
      setup_prelude()
      for _, bufnr in ipairs(attached_bufnrs()) do
        projection.force_render(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup_id,
    desc = "cleanup math-conceal image assets",
    callback = function()
      detach_all()
      require("math-conceal.image.workspace").cleanup_all()
    end,
  })
end

function M.setup(cfg)
  require("math-conceal.image.capability").assert_supported()
  detach_all()
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), cfg or {})
  if not vim.list_contains({ "colorscheme", "simple", "none" }, M.config.styling_type) then
    error("math-conceal image styling_type must be one of colorscheme, simple, none")
  end
  close_all_hidden_service_timers()
  M._buffers = {}
  cursor_sync_pending = {}
  cursor_sync_generation = {}
  resume_on_read = {}
  hidden_service_timers = {}
  setup_prelude()
  state.refresh_cell_px_size(M.config)
  build_filetype_index()
  setup_autocmds()
  attach_loaded_buffers()
end

return M
