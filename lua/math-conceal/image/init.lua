--- math-conceal.image public API
--- This file is intentionally thin: setup, enable/disable, and autocmd wiring.
--- All rendering logic lives in the sub-modules (semantics, wrapper, extmark, session, render).

--- @class typstconcealer
local M = {}

--- @type { [integer]: boolean }
M._enabled_buffers = {}

-- ── Terminal cell-size detection (FFI) ────────────────────────────────────────

local ffi = require("ffi")
ffi.cdef([[
  typedef struct { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; } winsize_t;
  int ioctl(int fd, unsigned long request, ...);
]])
local TIOCGWINSZ = vim.fn.has("mac") == 1 and 0x40087468 or 0x5413

--- Refresh the terminal cell pixel dimensions stored in state.
--- Called at setup time and on VimResized.
local function refresh_cell_px_size()
  local state = require("math-conceal.image.state")
  local old_cell_w = state._cell_px_w
  local old_cell_h = state._cell_px_h
  local old_ppi = state._render_ppi
  local ws = ffi.new("winsize_t")
  if ffi.C.ioctl(1, TIOCGWINSZ, ws) == 0 and ws.ws_xpixel > 0 and ws.ws_col > 0 then
    state._cell_px_w = ws.ws_xpixel / ws.ws_col
    state._cell_px_h = ws.ws_ypixel / ws.ws_row
    local baseline_pt = (M.config and M.config.math_baseline_pt) or 10
    state._render_ppi = math.max(72, math.floor(state._cell_px_h * 72 / baseline_pt))
  end
  return old_cell_w ~= state._cell_px_w or old_cell_h ~= state._cell_px_h or old_ppi ~= state._render_ppi
end

local last_resize_columns = vim.o.columns

local function handle_vim_resized()
  local previous_columns = last_resize_columns
  local render_inputs_changed = refresh_cell_px_size()
  local columns_changed = previous_columns ~= vim.o.columns
  last_resize_columns = vim.o.columns

  local runtime = require("math-conceal.image.machine.runtime")
  for bufnr in pairs(M._enabled_buffers) do
    if M.is_supported_bufnr(bufnr) and M.is_render_allowed(bufnr) then
      if render_inputs_changed or columns_changed then
        runtime.render_buf(bufnr)
      end
    end
  end
end

local function handle_win_resized()
  local affected_buffers = {}
  local windows = vim.v.event and vim.v.event.windows or nil
  if type(windows) ~= "table" or vim.tbl_isempty(windows) then
    windows = { vim.api.nvim_get_current_win() }
  end

  for _, winid in ipairs(windows) do
    if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      affected_buffers[vim.api.nvim_win_get_buf(winid)] = true
    end
  end

  if vim.tbl_isempty(affected_buffers) then
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) then
        affected_buffers[vim.api.nvim_win_get_buf(winid)] = true
      end
    end
  end

  local runtime = require("math-conceal.image.machine.runtime")
  for bufnr in pairs(affected_buffers) do
    if M._enabled_buffers[bufnr] == true and M.is_supported_bufnr(bufnr) and M.is_render_allowed(bufnr) then
      runtime.schedule_visible_overlay_refresh(bufnr, { immediate = true })
      runtime.schedule_full_render(bufnr)
    end
  end
end

M._handle_vim_resized = handle_vim_resized
M._handle_win_resized = handle_win_resized

-- ── Typst prelude / styling ────────────────────────────────────────────────────

--- Rebuild M._styling_prelude from the current colour scheme / styling config.
local function setup_prelude()
  if M.config.styling_type == "colorscheme" then
    local color = M.config.color
    if color == nil then
      color = string.format('rgb("#%06X")', vim.api.nvim_get_hl(0, { name = "Normal" })["fg"])
    end
    -- FIXME: lists everything. agony. hope https://github.com/typst/typst/issues/3356 is resolved.
    M._styling_prelude = ""
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
      .. "#set line(stroke: "
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
    M._styling_prelude = ""
      .. "#set page(width: auto, height: auto, margin: 0.75pt)\n"
      .. '#set text(top-edge: "ascender", bottom-edge: "descender")\n'
  elseif M.config.styling_type == "none" then
    M._styling_prelude = ""
  end
end

-- ── Public API ─────────────────────────────────────────────────────────────────

--- @class typstconfig
--- @field use_formula_service?   boolean   Use formula-level compiler-service requests for full overlays. Default true.
--- @field formula_worker_count?  integer   Worker count for formula-level service batches. Default 2.
--- @field service_binary?        string    Path to typst-concealer-service. Defaults to "typst-concealer-service".
--- @field do_diagnostics?        boolean   Provide diagnostics on compile error.
--- @field color?                 string    Render colour (only when styling_type = "colorscheme").
--- @field enabled_by_default?    boolean   Conceal newly opened buffers by default.
--- @field styling_type?          "none"|"simple"|"colorscheme"  Styling strategy.
--- @field ppi?                   integer   Fallback PPI when terminal pixel size is unavailable.
--- @field math_baseline_pt?      number    Expected math line height in pt for 1 terminal row. Default 11.
--- @field conceal_in_normal      boolean   Keep concealing when the cursor is on a line in normal mode.
--- @field compiler_args?         string[]  Backward-compatible `--input` arguments consumed by the service.
--- @field header?                string    Custom Typst code prepended to every rendered document.
--- @field mitex_package?         string    Typst package spec used for Markdown LaTeX math. Default "@preview/mitex:0.2.7".
--- @field markdown_filetypes?    string[]  Filetypes treated as Markdown math sources. Default { "markdown" }.
--- @field filetypes?             string[]  Filetypes/path-kinds managed by image conceal. Default { "typst", "markdown" }.
--- @field backends?              { latex?: latexbackendconfig }
--- @field block_padding_cols?    integer   Terminal columns reserved as outer padding for code blocks.
--- @field block_preview_margin_pt? number  Extra Typst-side inner margin for code block previews.
--- @field live_preview_enabled?  boolean   Enable inline live preview around the active math node. Default true.
--- @field live_preview_debounce? number    Debounce delay for live preview in ms. Default 100.
--- @field cursor_hover_throttle_ms? number  Throttle delay for CursorMoved hover in ms. Default 0 (disabled).
--- @field render_paths?          { include?: (string|fun(path: string, bufnr: integer): boolean)[], exclude?: (string|fun(path: string, bufnr: integer): boolean)[] }
---                                     Optional path rules. `include` acts as a whitelist when non-empty; `exclude` always wins.
--- @field get_root?              fun(bufnr: integer, path: string, cwd: string, kind: "full"): string|nil
---                                     Return the Typst root base passed to `--root` and used to interpret rooted paths
---                                     like `/fig/a.png`. Must be an absolute filesystem path. `nil` falls back to the
---                                     detected project root, then to the buffer directory/current working directory.
--- @field get_inputs?            fun(bufnr: integer, path: string, cwd: string, kind: "full"): string[]|nil
---                                     Return extra `--input` values, e.g. `{"focus=123", "preview=true"}`. `nil`/`{}` appends nothing.
--- @field get_preamble_file?     fun(bufnr: integer, path: string, cwd: string, kind: "full"): string|nil
---                                     Return an absolute path to a `.typ` file that is `#include`d at the top of every
---                                     batch document for this buffer. Use this to inject project-level context
---                                     (bibliography, imports, show rules) so that snippets compile under the correct
---                                     project scope. The file must be within `--root`. `nil` skips injection.
---
--- @class latexbackendconfig
--- @field enabled?               boolean   Enable LaTeX math rendering support. Default false.
--- @field compiler?              string    LaTeX compiler executable. Default "pdflatex".
--- @field converter?             string    PDF-to-PNG converter executable. Default "pdftocairo".
--- @field compiler_args?         string[]  Extra compiler arguments.
--- @field header?                string    Custom LaTeX preamble inserted before project preamble.
--- @field mitex_fast_path?       boolean   Try Typst/MiTeX rendering before falling back to full LaTeX. Default true.
--- @field viewport_margin?       integer   Extra screen rows around visible windows rendered by LaTeX. Default 0.
--- @field get_root?              fun(bufnr: integer, path: string, cwd: string, kind: "full"): string|nil
--- @field get_main_file?         fun(bufnr: integer, path: string, cwd: string, kind: "full"): string|nil
--- @field get_preamble_file?     fun(bufnr: integer, path: string, cwd: string, kind: "full"): string|nil

local function default(val, default_val)
  if val == nil then
    return default_val
  end
  return val
end

local augroup = vim.api.nvim_create_augroup("math-conceal.image", { clear = true })

local function normalize_path(path)
  if path == nil or path == "" then
    return ""
  end
  return vim.fs.normalize(path)
end

local function latex_config()
  return M.config and M.config.backends and M.config.backends.latex or nil
end

local function latex_enabled()
  local cfg = latex_config()
  return cfg ~= nil and cfg.enabled == true
end

local function source_kind_from_path(path)
  path = path or ""
  if path:match("%.typ$") then
    return "typst"
  elseif path:match("%.md$") or path:match("%.markdown$") then
    return "markdown"
  elseif latex_enabled() and path:match("%.tex$") then
    return "latex"
  end
  return nil
end

local function markdown_filetypes()
  if M.config == nil or M.config.markdown_filetypes == nil then
    return { "markdown" }
  end
  return M.config.markdown_filetypes
end

local function filetype_in(list, ft)
  for _, candidate in ipairs(list or {}) do
    if candidate == ft then
      return true
    end
  end
  return false
end

local function source_kind_enabled(kind)
  if M.config == nil or M.config.filetypes == nil then
    return kind == "typst" or kind == "markdown"
  end

  for _, ft in ipairs(M.config.filetypes) do
    if ft == kind or (kind == "latex" and vim.list_contains({ "tex", "plaintex", "latex" }, ft)) then
      return true
    end
  end
  return false
end

local function parser_available(lang, probe_query)
  if vim.treesitter.language and type(vim.treesitter.language.inspect) == "function" then
    return pcall(vim.treesitter.language.inspect, lang)
  end
  return pcall(vim.treesitter.query.parse, lang, probe_query)
end

function M.source_kind_for_bufnr(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ft = vim.bo[bufnr].filetype
  if ft == "typst" then
    return source_kind_enabled("typst") and "typst" or nil
  elseif latex_enabled() and vim.list_contains({ "tex", "plaintex", "latex" }, ft) then
    return source_kind_enabled("latex") and "latex" or nil
  elseif filetype_in(markdown_filetypes(), ft) then
    return source_kind_enabled("markdown") and "markdown" or nil
  end

  local kind = source_kind_from_path(vim.api.nvim_buf_get_name(bufnr))
  if kind ~= nil and source_kind_enabled(kind) then
    return kind
  end
  return nil
end

function M.is_supported_bufnr(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  return M.source_kind_for_bufnr(bufnr) ~= nil
end

local function matches_path_rule(rule, path, bufnr)
  if type(rule) == "string" then
    return path:match(rule) ~= nil
  end
  if type(rule) == "function" then
    local ok, matched = pcall(rule, path, bufnr)
    return ok and matched == true
  end
  return false
end

local function matches_any_path_rule(rules, path, bufnr)
  for _, rule in ipairs(rules or {}) do
    if matches_path_rule(rule, path, bufnr) then
      return true
    end
  end
  return false
end

local function buf_has_visible_window(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      return true
    end
  end
  return false
end

local function maybe_stop_hidden_compiler_service(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not M.is_supported_bufnr(bufnr) or M._enabled_buffers[bufnr] ~= true then
    return
  end
  if buf_has_visible_window(bufnr) then
    return
  end
  require("math-conceal.image.session").stop_compiler_service(bufnr)
end

local function maybe_resume_visible_compiler_service(bufnr)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not M.is_supported_bufnr(bufnr)
    or M._enabled_buffers[bufnr] ~= true
    or not M.is_render_allowed(bufnr)
    or not buf_has_visible_window(bufnr)
  then
    return
  end

  local session = require("math-conceal.image.session")
  if session.has_compiler_service(bufnr) then
    return
  end
  require("math-conceal.image.machine.runtime").render_buf(bufnr)
end

local function schedule_render_if_viewport_changed(bufnr)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not M.is_supported_bufnr(bufnr)
    or M._enabled_buffers[bufnr] ~= true
    or not M.is_render_allowed(bufnr)
  then
    return
  end

  local changed = require("math-conceal.image.viewport").changed_since_last_render(bufnr)
  if changed then
    require("math-conceal.image.machine.runtime").schedule_full_render(bufnr)
  end
end

local function cleanup_image_assets_on_exit()
  local state = require("math-conceal.image.state")
  local session = require("math-conceal.image.session")
  local seen = {}

  for bufnr in pairs(M._enabled_buffers or {}) do
    seen[bufnr] = true
  end
  for bufnr in pairs(state.compiler_services or {}) do
    seen[bufnr] = true
  end
  for bufnr in pairs(state.service_cache_dirs or {}) do
    seen[bufnr] = true
  end
  for bufnr in pairs(state.service_workspace_dirs or {}) do
    seen[bufnr] = true
  end

  for bufnr in pairs(seen) do
    session.stop_compiler_service(bufnr)
    state.clear_preview_timer(bufnr)
  end

  require("math-conceal.image.workspace").cleanup_all()
end

local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "\22"
end

local function mode_changed_involves_visual(match)
  local old_mode, new_mode = tostring(match or ""):match("^([^:]*):(.*)$")
  return is_visual_mode(old_mode) or is_visual_mode(new_mode)
end

local function sync_cursor_ui_on_visual_mode_changed(bufnr, match)
  if not mode_changed_involves_visual(match) then
    return
  end
  require("math-conceal.image.machine.runtime").sync_cursor_ui(bufnr)
end

local function attach_buffer_local_autocmds(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not M.is_supported_bufnr(bufnr) then
    return
  end
  if source_kind_from_path(vim.api.nvim_buf_get_name(bufnr)) ~= nil then
    return
  end

  local bs = require("math-conceal.image.state").get_buf_state(bufnr)
  if bs.buffer_local_autocmds_attached then
    return
  end
  bs.buffer_local_autocmds_attached = true

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = bufnr,
    desc = "unconceal on line hover",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").sync_cursor_ui(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    buffer = bufnr,
    desc = "sync source reveal when entering or leaving visual mode",
    callback = function(ev)
      sync_cursor_ui_on_visual_mode_changed(ev.buf, ev.match)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    buffer = bufnr,
    desc = "keep float preview synced while moving in insert mode",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").schedule_live_preview_sync(ev.buf, { immediate = true })
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    buffer = bufnr,
    desc = "render live preview float when insert-mode text changes",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").schedule_live_preview_sync(ev.buf, { refresh_full = true })
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    buffer = bufnr,
    desc = "sync float preview when entering a supported buffer",
    callback = function(ev)
      vim.schedule(function()
        maybe_resume_visible_compiler_service(ev.buf)
        schedule_render_if_viewport_changed(ev.buf)
        local runtime = require("math-conceal.image.machine.runtime")
        runtime.render_live_preview(ev.buf)
        runtime.sync_hover(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "BufHidden", "BufDelete" }, {
    group = augroup,
    buffer = bufnr,
    desc = "clear live preview when leaving a supported buffer",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").clear_live_preview(ev.buf)
      vim.schedule(function()
        maybe_stop_hidden_compiler_service(ev.buf)
      end)
    end,
  })
end

function M.is_render_allowed(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local path = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local render_paths = (M.config and M.config.render_paths) or {}
  local includes = render_paths.include or {}
  local excludes = render_paths.exclude or {}

  if #includes > 0 and not matches_any_path_rule(includes, path, bufnr) then
    return false
  end

  if matches_any_path_rule(excludes, path, bufnr) then
    return false
  end

  return true
end

M.enable_buf = function(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not M.is_render_allowed(bufnr) then
    M._enabled_buffers[bufnr] = nil
    require("math-conceal.image.plan").hard_reset_buf(bufnr)
    return
  end
  M._enabled_buffers[bufnr] = true
  require("math-conceal.image.machine.runtime").render_buf(bufnr)
end

M.disable_buf = function(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  M._enabled_buffers[bufnr] = nil
  require("math-conceal.image.state").clear_hover_timer(bufnr)
  local session = require("math-conceal.image.session")
  session.stop_compiler_service(bufnr)
  require("math-conceal.image.machine.runtime").clear_live_preview(bufnr)
  require("math-conceal.image.plan").hard_reset_buf(bufnr)
end

M.toggle_buf = function(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if M._enabled_buffers[bufnr] ~= nil then
    M.disable_buf(bufnr)
  else
    M.enable_buf(bufnr)
  end
end

M.rerender_buf = function(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  require("math-conceal.image.machine.runtime").render_buf(bufnr)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup(cfg)
  local version = vim.version()
  if version.major == 0 and version.minor < 10 then
    error("Typst concealer requires at least nvim 10.0 to work")
  end

  if M._setup_ran ~= nil then
    error("math-conceal.image's setup function may only be run once")
  end
  M._setup_ran = true
  cfg = cfg or {}

  local latex_cfg = (cfg.backends and cfg.backends.latex) or {}

  M.config = {
    use_formula_service = default(cfg.use_formula_service, true),
    formula_worker_count = default(cfg.formula_worker_count, 2),
    service_binary = default(cfg.service_binary, "typst-concealer-service"),
    do_diagnostics = default(cfg.do_diagnostics, true),
    enabled_by_default = default(cfg.enabled_by_default, true),
    styling_type = default(cfg.styling_type, "colorscheme"),
    ppi = default(cfg.ppi, 300),
    math_baseline_pt = default(cfg.math_baseline_pt, 11),
    color = cfg.color,
    conceal_in_normal = default(cfg.conceal_in_normal, false),
    compiler_args = default(cfg.compiler_args, {}),
    header = default(cfg.header, ""),
    mitex_package = default(cfg.mitex_package, "@preview/mitex:0.2.7"),
    filetypes = default(cfg.filetypes, { "typst", "markdown" }),
    markdown_filetypes = default(cfg.markdown_filetypes, { "markdown" }),
    block_padding_cols = default(cfg.block_padding_cols, 15),
    block_preview_margin_pt = default(cfg.block_preview_margin_pt, 6),
    live_preview_enabled = default(cfg.live_preview_enabled, true),
    live_preview_debounce = default(cfg.live_preview_debounce, 100),
    cursor_hover_throttle_ms = default(cfg.cursor_hover_throttle_ms, 0),
    render_paths = default(cfg.render_paths, {}),
    get_root = cfg.get_root,
    get_inputs = cfg.get_inputs,
    get_preamble_file = cfg.get_preamble_file,
    backends = {
      latex = {
        enabled = default(latex_cfg.enabled, false),
        compiler = default(latex_cfg.compiler, "pdflatex"),
        converter = default(latex_cfg.converter, "pdftocairo"),
        compiler_args = default(latex_cfg.compiler_args, {}),
        header = default(latex_cfg.header, ""),
        mitex_fast_path = default(latex_cfg.mitex_fast_path, true),
        viewport_margin = default(latex_cfg.viewport_margin, 0),
        get_root = latex_cfg.get_root,
        get_main_file = latex_cfg.get_main_file,
        get_preamble_file = latex_cfg.get_preamble_file,
      },
    },
  }

  if not vim.list_contains({ "none", "simple", "colorscheme" }, M.config.styling_type) then
    error(
      "typst styling_type "
        .. M.config.styling_type
        .. " is not a valid option. Please use 'none', 'simple' or 'colorscheme'"
    )
  end

  if M.config.get_root ~= nil and type(M.config.get_root) ~= "function" then
    error("typst get_root must be a function when provided")
  end

  local latex_backend_cfg = M.config.backends.latex
  if type(latex_backend_cfg.compiler_args) ~= "table" then
    error("backends.latex.compiler_args must be a list of strings")
  end
  for _, arg in ipairs(latex_backend_cfg.compiler_args) do
    if type(arg) ~= "string" then
      error("backends.latex.compiler_args must be a list of strings")
    end
  end
  if type(latex_backend_cfg.viewport_margin) ~= "number" or latex_backend_cfg.viewport_margin < 0 then
    error("backends.latex.viewport_margin must be a non-negative number")
  end
  if type(latex_backend_cfg.mitex_fast_path) ~= "boolean" then
    error("backends.latex.mitex_fast_path must be a boolean")
  end
  for _, key in ipairs({ "get_root", "get_main_file", "get_preamble_file" }) do
    if latex_backend_cfg[key] ~= nil and type(latex_backend_cfg[key]) ~= "function" then
      error("backends.latex." .. key .. " must be a function when provided")
    end
  end

  if type(M.config.markdown_filetypes) ~= "table" then
    error("typst markdown_filetypes must be a list of filetype strings")
  end
  if type(M.config.filetypes) ~= "table" then
    error("typst filetypes must be a list of filetype strings")
  end
  for _, ft in ipairs(M.config.filetypes) do
    if type(ft) ~= "string" then
      error("typst filetypes must be a list of filetype strings")
    end
  end
  for _, ft in ipairs(M.config.markdown_filetypes) do
    if type(ft) ~= "string" then
      error("typst markdown_filetypes must be a list of filetype strings")
    end
  end

  setup_prelude()
  refresh_cell_px_size()
  last_resize_columns = vim.o.columns

  local typst_parser_installed = parser_available("typst", "(math) @math")
  if typst_parser_installed == false then
    error("Typst treesitter parser not found, math-conceal.image will not work")
  end

  if latex_backend_cfg.enabled == true then
    local latex_parser_ok = parser_available("latex", "(inline_formula) @math")
    if not latex_parser_ok then
      vim.notify(
        "[math-conceal.image] LaTeX backend enabled but 'latex' tree-sitter parser is unavailable",
        vim.log.levels.WARN
      )
    end
    if vim.fn.executable(latex_backend_cfg.compiler) ~= 1 then
      vim.notify(
        ("[math-conceal.image] LaTeX backend enabled but compiler '%s' is unavailable"):format(
          latex_backend_cfg.compiler
        ),
        vim.log.levels.WARN
      )
    end
    if vim.fn.executable(latex_backend_cfg.converter) ~= 1 then
      vim.notify(
        ("[math-conceal.image] LaTeX backend enabled but converter '%s' is unavailable"):format(
          latex_backend_cfg.converter
        ),
        vim.log.levels.WARN
      )
    end
  end

  M._typst_query = vim.treesitter.query.parse(
    "typst",
    [[
[
 (code
  [(_) (call item: (ident) @call_ident)] @code
 )
 (math)
] @block
]]
  )

  -- ── Per-buffer initialisation ──────────────────────────────────────────────

  local function init_buf(bufnr)
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nci"
    attach_buffer_local_autocmds(bufnr)
    local bs = require("math-conceal.image.state").get_buf_state(bufnr)
    if not bs.change_tracker_attached then
      vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function(_, buf, _, firstline, lastline, new_lastline)
          local state_mod = require("math-conceal.image.state")
          local tracked = state_mod.get_buf_state(buf)
          local old_end_row = math.max(firstline, lastline) - 1
          local new_end_row = math.max(firstline, new_lastline) - 1
          local line_delta = new_lastline - lastline
          local ok_extmark, extmark = pcall(require, "math-conceal.image.extmark")
          if ok_extmark and type(extmark.clear_inline_line_marks) == "function" then
            if line_delta == 0 then
              extmark.clear_inline_line_marks(buf, firstline, math.max(old_end_row, new_end_row))
            else
              extmark.clear_inline_line_marks(buf, firstline)
            end
          end
          local pending = tracked.pending_change
          if pending == nil then
            tracked.pending_change = {
              start_row = firstline,
              old_end_row = old_end_row,
              new_end_row = new_end_row,
              line_delta = line_delta,
              requires_full = line_delta ~= 0,
            }
            require("math-conceal.image.machine.runtime").schedule_full_render(buf)
            return
          end
          pending.start_row = math.min(pending.start_row, firstline)
          pending.old_end_row = math.max(pending.old_end_row, old_end_row)
          pending.new_end_row = math.max(pending.new_end_row, new_end_row)
          pending.line_delta = pending.line_delta + line_delta
          pending.requires_full = pending.requires_full or line_delta ~= 0
          require("math-conceal.image.machine.runtime").schedule_full_render(buf)
        end,
        on_bytes = function(
          _event,
          buf,
          _changedtick,
          start_row,
          start_col,
          _byte_offset,
          _old_end_row,
          _old_end_col,
          _old_byte_len,
          new_end_row,
          new_end_col,
          _new_byte_len
        )
          local state_mod = require("math-conceal.image.state")
          local tracked = state_mod.get_buf_state(buf)
          local end_row = start_row + new_end_row
          local end_col = new_end_row == 0 and (start_col + new_end_col) or new_end_col
          tracked.binding_dirty_ranges = tracked.binding_dirty_ranges or {}
          tracked.binding_dirty_ranges[#tracked.binding_dirty_ranges + 1] = {
            start_row,
            start_col,
            end_row,
            end_col,
          }
        end,
        on_detach = function(_, buf)
          local state_mod = require("math-conceal.image.state")
          local tracked = state_mod.get_buf_state(buf)
          tracked.change_tracker_attached = false
          tracked.pending_change = nil
          tracked.binding_dirty_ranges = nil
        end,
      })
      bs.change_tracker_attached = true
    end
    if M.config.enabled_by_default and M.is_render_allowed(bufnr) then
      M._enabled_buffers[bufnr] = true
    else
      M._enabled_buffers[bufnr] = nil
    end
  end

  if vim.v.vim_did_enter then
    local bufnr = vim.fn.bufnr()
    if M.is_supported_bufnr(bufnr) then
      init_buf(bufnr)
    end
  end

  -- ── Autocmds ──────────────────────────────────────────────────────────────

  local managed_patterns = {}
  if source_kind_enabled("typst") then
    managed_patterns[#managed_patterns + 1] = "*.typ"
  end
  if source_kind_enabled("markdown") then
    managed_patterns[#managed_patterns + 1] = "*.md"
    managed_patterns[#managed_patterns + 1] = "*.markdown"
  end
  if latex_backend_cfg.enabled == true then
    managed_patterns[#managed_patterns + 1] = "*.tex"
  end

  local managed_filetypes = {}
  if source_kind_enabled("typst") then
    managed_filetypes[#managed_filetypes + 1] = "typst"
  end
  if source_kind_enabled("markdown") then
    vim.list_extend(managed_filetypes, vim.deepcopy(M.config.markdown_filetypes))
  end
  if latex_backend_cfg.enabled == true then
    managed_filetypes[#managed_filetypes + 1] = "tex"
    managed_filetypes[#managed_filetypes + 1] = "plaintex"
    managed_filetypes[#managed_filetypes + 1] = "latex"
  end

  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = managed_patterns,
    group = augroup,
    desc = "render file on enter",
    callback = function(ev)
      vim.schedule(function()
        require("math-conceal.image.machine.runtime").render_buf(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufNew", "VimEnter" }, {
    pattern = managed_patterns,
    group = augroup,
    desc = "enable file on creation if the option is set",
    callback = function(ev)
      init_buf(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = managed_patterns,
    group = augroup,
    desc = "render file on write",
    callback = function(ev)
      vim.schedule(function()
        require("math-conceal.image.machine.runtime").render_buf(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("TextChanged", {
    pattern = managed_patterns,
    group = augroup,
    desc = "re-render on normal-mode text changes so block anchors stay correct",
    callback = function(ev)
      vim.schedule(function()
        local runtime = require("math-conceal.image.machine.runtime")
        runtime.schedule_full_render(ev.buf, { immediate = true })
        runtime.render_live_preview(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    pattern = managed_patterns,
    group = augroup,
    desc = "unconceal on line hover",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").sync_cursor_ui(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "ModeChanged" }, {
    group = augroup,
    desc = "sync source reveal when entering or leaving visual mode",
    callback = function(ev)
      local bufnr = ev.buf
      if bufnr == nil or bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
      end
      if M.is_supported_bufnr(bufnr) then
        sync_cursor_ui_on_visual_mode_changed(bufnr, ev.match)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    pattern = managed_patterns,
    desc = "keep float preview synced while moving in insert mode",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").schedule_live_preview_sync(ev.buf, { immediate = true })
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    pattern = managed_patterns,
    desc = "sync float preview when entering a supported buffer",
    callback = function(ev)
      vim.schedule(function()
        maybe_resume_visible_compiler_service(ev.buf)
        schedule_render_if_viewport_changed(ev.buf)
        local runtime = require("math-conceal.image.machine.runtime")
        runtime.render_live_preview(ev.buf)
        runtime.sync_hover(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    pattern = managed_patterns,
    desc = "resume compiler service when a supported buffer becomes visible",
    callback = function(ev)
      vim.schedule(function()
        maybe_resume_visible_compiler_service(ev.buf)
        schedule_render_if_viewport_changed(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    desc = "render buffers whose adapter viewport follows visible windows",
    callback = function()
      vim.schedule(function()
        local seen = {}
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(winid) then
            local bufnr = vim.api.nvim_win_get_buf(winid)
            if not seen[bufnr] then
              seen[bufnr] = true
              schedule_render_if_viewport_changed(bufnr)
            end
          end
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    pattern = managed_patterns,
    group = augroup,
    desc = "render live preview float when insert-mode text changes",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").schedule_live_preview_sync(ev.buf, { refresh_full = true })
    end,
  })

  if cfg.color == nil then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = augroup,
      desc = "update colour scheme",
      callback = function()
        setup_prelude()
        local runtime = require("math-conceal.image.machine.runtime")
        for bufnr in pairs(M._enabled_buffers) do
          runtime.render_buf(bufnr)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = managed_filetypes,
    callback = function(ev)
      init_buf(ev.buf)
      if M._enabled_buffers[ev.buf] == true and M.is_render_allowed(ev.buf) then
        require("math-conceal.image.machine.runtime").render_buf(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    desc = "refresh cell pixel size on terminal resize",
    callback = handle_vim_resized,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    desc = "refresh image conceal when window dimensions change",
    callback = handle_win_resized,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    desc = "remove math-conceal image assets from the Neovim cache",
    callback = cleanup_image_assets_on_exit,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "BufHidden", "BufDelete" }, {
    pattern = managed_patterns,
    group = augroup,
    desc = "clear live preview when leaving a typst buffer",
    callback = function(ev)
      require("math-conceal.image.machine.runtime").clear_live_preview(ev.buf)
      vim.schedule(function()
        maybe_stop_hidden_compiler_service(ev.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    desc = "stop compiler service when a typst buffer is no longer visible",
    callback = function()
      vim.schedule(function()
        for bufnr in pairs(M._enabled_buffers) do
          maybe_stop_hidden_compiler_service(bufnr)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = augroup,
    pattern = managed_patterns,
    desc = "stop compiler service for dead buffers",
    callback = function(ev)
      local session = require("math-conceal.image.session")
      session.stop_compiler_service(ev.buf)
      require("math-conceal.image.state").clear_preview_timer(ev.buf)
      require("math-conceal.image.plan").hard_reset_buf(ev.buf)
    end,
  })
end

return M
