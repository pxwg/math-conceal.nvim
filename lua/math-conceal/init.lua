local queries = require("math-conceal.query")
local render = require("math-conceal.render")
local window_options = require("math-conceal.window-options")
local M = {
  files = {},
  queries = {},
  -- Default options
  --- @type MathConcealOptions
  opts = {
    conceal = {
      "greek",
      "script",
      "math",
      "font",
      "delim",
      "phy",
    },
    ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
    opt = {
      conceallevel = 2,
      concealcursor = "n",
    },
    depth = 90,
    ns_id = 0,
    buffer = {
      mode = "edit",
    },
    integrations = {
      snacks = {
        enabled = true,
      },
    },
    image = {
      enabled = false,
      enabled_by_default = true,
      live_preview_enabled = true,
      preview_idle_timeout_ms = 1000,
      hidden_service_idle_ms = 2000,
      tracker = {
        debug = false,
      },
      renderers = {
        typst = {
          filetypes = { "typst" },
          live_debounce = 0,
          code_render = {
            allow = {},
          },
        },
        markdown = {
          filetypes = { "markdown" },
          live_debounce = 0,
        },
      },
    },
    highlights = {
      ["@_env"] = { link = "@conceal", default = true },
      ["@_frac_name"] = { link = "@conceal", default = true },
      ["@_func_name"] = { link = "@conceal", default = true },
      ["@_line"] = { link = "@conceal", default = true },
      ["@_tagged"] = { link = "@conceal", default = true },
      ["@abs_name"] = { link = "@conceal", default = true },
      ["@close_paren"] = { link = "@conceal", default = true },
      ["@cmd"] = { link = "@conceal", default = true },
      ["@cmd_escape"] = { link = "@conceal", default = true },
      ["@comma"] = { link = "@conceal", default = true },
      ["@conceal"] = { link = "Conceal", default = true },
      ["@conceal_dollar"] = { link = "@conceal", default = true },
      ["@content"] = { link = "@conceal", default = true },
      ["@first_letter"] = { link = "@conceal", default = true },
      ["@font_letter"] = { link = "@conceal", default = true },
      ["@font_digit"] = { link = "@conceal", default = true },
      ["@frac"] = { link = "@conceal", default = true },
      ["@func"] = { link = "@conceal", default = true },
      ["@func_name"] = { link = "@conceal", default = true },
      ["@left_1"] = { link = "@conceal", default = true },
      ["@left_2"] = { link = "@conceal", default = true },
      ["@left_brace"] = { link = "@conceal", default = true },
      ["@left_content"] = { link = "@conceal", default = true },
      ["@left_paren"] = { link = "@conceal", default = true },
      ["@left_paren_cmd"] = { link = "@conceal", default = true },
      ["@open_paren"] = { link = "@conceal", default = true },
      ["@punctuation"] = { link = "@conceal", default = true },
      ["@right_1"] = { link = "@conceal", default = true },
      ["@right_2"] = { link = "@conceal", default = true },
      ["@right_brace"] = { link = "@conceal", default = true },
      ["@right_content"] = { link = "@conceal", default = true },
      ["@right_paren"] = { link = "@conceal", default = true },
      ["@right_paren_cmd"] = { link = "@conceal", default = true },
      ["@second_letter"] = { link = "@conceal", default = true },
      ["@sub_digit"] = { link = "@conceal", default = true },
      ["@sub_letter"] = { link = "@conceal", default = true },
      ["@sub_object"] = { link = "@conceal", default = true },
      ["@sub_string"] = { link = "@string.typst", default = true },
      ["@sub_symbol"] = { link = "@conceal", default = true },
      ["@sup_digit"] = { link = "@conceal", default = true },
      ["@sup_letter"] = { link = "@conceal", default = true },
      ["@sup_object"] = { link = "@conceal", default = true },
      ["@sup_string"] = { link = "@string.typst", default = true },
      ["@sup_symbol"] = { link = "@conceal", default = true },
      ["@symbol"] = { link = "@conceal", default = true },
      ["@tex_font_name"] = { link = "@conceal", default = true },
      ["@tex_greek"] = { link = "@conceal", default = true },
      ["@tex_math_command"] = { link = "@conceal", default = true },
      ["@typ_font_name"] = { link = "@conceal", default = true },
      ["@typ_greek_symbol"] = { link = "@conceal", default = true },
      ["@typ_inline_ampersand"] = { link = "@conceal", default = true },
      ["@typ_inline_asterisk"] = { link = "@conceal", default = true },
      ["@typ_inline_dollar"] = { link = "@conceal", default = true },
      ["@typ_inline_quote"] = { link = "@conceal", default = true },
      ["@typ_math_delim"] = { link = "@conceal", default = true },
      ["@typ_math_font"] = { link = "@conceal", default = true },
      ["@typ_math_symbol"] = { link = "@conceal", default = true },
      ["@typ_phy_symbol"] = { link = "@conceal", default = true },
      ["@typ_symbol"] = { link = "@conceal", default = true },
    },
  },
}

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class MathConcealOptions
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable conceal
--- @field opt MathConcealWindowOptions?: Window-local Neovim conceal options applied to attached buffers.
--- @field depth integer
--- @field augroup_id integer?
--- @field ns_id integer
--- @field buffer MathConcealBufferOptions?
--- @field highlights table<string, table<string, string>>
--- @field integrations MathConcealIntegrationsOptions?
--- @field image MathConcealImageOptions?

--- @class MathConcealIntegrationsOptions
--- @field snacks MathConcealSnacksIntegrationOptions|false?

--- @class MathConcealSnacksIntegrationOptions
--- @field enabled boolean?
--- @field unicode boolean?
--- @field image boolean?
--- @field mode "edit"|"preview"|"presentation"|false?
--- @field surfaces MathConcealAttachSurfaces?
--- @field source string|table|fun(ctx: table, bufnr: integer, source: table): table?
--- @field filetype string|fun(ctx: table, bufnr: integer, path: string): string?

--- @class MathConcealWindowOptions
--- @field conceallevel integer?: Window-local conceallevel for attached buffers. Default 2.
--- @field concealcursor string?: Window-local concealcursor for attached buffers. Default "n".

--- @class MathConcealBufferOptions
--- @field mode "edit"|"preview"|"presentation"?: Conceal cursor behavior. `edit` expands the item under the cursor; `preview` keeps ASCII/Unicode items concealed; `presentation` keeps plugin-managed ASCII/Unicode conceal collapsed, except while Visual selection reveals source for precise selection.

--- @class MathConcealImageOptions
--- @field enabled boolean?: Enable image renderer attachment. Default false.
--- @field enabled_by_default boolean?: Attach matching buffers automatically. Default true.
--- @field live_preview_enabled boolean?: Enable cursor-following live preview. Default true.
--- @field preview_idle_timeout_ms integer?: Stop the idle live preview service after this many milliseconds. Default 1000.
--- @field hidden_service_idle_ms integer?: Stop services for hidden buffers after this many idle milliseconds. Default 2000.
--- @field tracker MathConcealImageTrackerOptions?: Tracker configuration for the image path.
--- @field renderers table<string, MathConcealImageRendererOptions>?: Renderer-specific attachment configuration.
--- Other fields are stored by `math-conceal.image` for the future renderer.

--- @class MathConcealImageTrackerOptions
--- @field debug boolean?: Show tracker debug projection extmarks. Default false.

--- @class MathConcealImageRendererOptions
--- @field filetypes string[]?: Neovim filetypes that should attach this renderer.
--- @field service_binary string?: Renderer service executable path.
--- @field live_debounce integer?: Text-change live preview debounce in milliseconds for this renderer.
--- @field source_kind string?: Scanner source kind. Defaults to the renderer name.
--- @field scanner string?: Scanner module key. Defaults to source_kind.
--- @field backend string?: Rust service backend. Markdown uses the Typst backend with a MiTeX wrapper.
--- @field wrapper string?: Render input wrapper. Markdown uses "mitex".
--- @field root string|fun(ctx: table): string?: Project root resolver for the renderer.
--- @field inputs table<string, string>|fun(ctx: table): table<string, string>?: Typst-like input values.
--- @field header string?: Renderer-scoped Typst header.
--- @field preamble_file string|fun(ctx: table): string?: Renderer-scoped Typst preamble file.
--- @field mitex_package string?: Typst package spec for Markdown MiTeX rendering.
--- @field code_render table?: Typst code rendering policy. `allow` adds global user names to the built-in safe allowlist.
--- @field render_paths table?: Path filters for renderer attachment.

--- @class MathConcealSource
--- @field kind "latex"|"markdown"|"typst"
--- @field filetype string
--- @field path string
--- @field cwd string
--- @field root_lang "latex"|"markdown"|"typst"
--- @field conceal_lang "latex"|"typst"
--- @field renderer string?

--- @class MathConcealAttachSurfaces
--- @field unicode boolean?
--- @field image boolean?

--- @class MathConcealAttachOptions
--- @field source string|table?
--- @field surfaces MathConcealAttachSurfaces?
--- @field mode "edit"|"preview"|"presentation"?
--- @field owner any?

local function module_source_path()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    return source:sub(2)
  end
end

local function plugin_root()
  local init_path = module_source_path()
  if init_path then
    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(init_path)))
  end
end

local function service_executable_name()
  return vim.fn.has("win32") == 1 and "typst-concealer-service.exe" or "typst-concealer-service"
end

local function path_join(parts)
  return table.concat(parts, "/")
end

local function path_exists(path)
  return path ~= nil and path ~= "" and vim.uv.fs_stat(path) ~= nil
end

local function rocks_tree_root()
  local init_path = module_source_path()
  if not init_path then
    return nil
  end
  init_path = init_path:gsub("\\", "/")
  return init_path:match("^(.*)/share/lua/[^/]+/math%-conceal/init%.lua$")
end

local function configured_rocks_roots()
  local roots = {}
  local rocks_nvim = vim.g.rocks_nvim
  if type(rocks_nvim) == "table" and type(rocks_nvim.rocks_path) == "string" then
    table.insert(roots, rocks_nvim.rocks_path)
  end
  table.insert(roots, path_join({ vim.fn.stdpath("data"), "rocks" }))
  return roots
end

local function bundled_service_binary()
  local exe = service_executable_name()
  local candidates = {}

  local root = plugin_root()
  if root then
    table.insert(candidates, path_join({ root, "service", "target", "release", exe }))
  end

  local rocks_root = rocks_tree_root()
  if rocks_root then
    table.insert(candidates, path_join({ rocks_root, "bin", exe }))
  end

  for _, candidate_root in ipairs(configured_rocks_roots()) do
    table.insert(candidates, path_join({ candidate_root, "bin", exe }))
  end

  local path_service = vim.fn.exepath(exe)
  if path_service ~= "" then
    table.insert(candidates, path_service)
  end

  for _, candidate in ipairs(candidates) do
    if path_exists(candidate) then
      return candidate
    end
  end
end

local source_profiles = {
  latex = {
    root_lang = "latex",
    conceal_lang = "latex",
  },
  markdown = {
    root_lang = "markdown",
    conceal_lang = "latex",
    renderer = "markdown",
  },
  typst = {
    root_lang = "typst",
    conceal_lang = "typst",
    renderer = "typst",
  },
}

local filetype_source_kinds = {
  bibtex = "latex",
  context = "latex",
  markdown = "markdown",
  plaintex = "latex",
  tex = "latex",
  typst = "typst",
}

local attachments = {}
local attachment_serial = 0
local unicode_base_setup = false
local render_languages_setup = {}
local markdown_highlights_setup = false
local attachment_augroup = vim.api.nvim_create_augroup("math-conceal.attachments", { clear = true })
local attachment_handle_mt = {}
attachment_handle_mt.__index = attachment_handle_mt

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

local function list_contains(values, wanted)
  for _, value in ipairs(values or {}) do
    if value == wanted then
      return true
    end
  end
  return false
end

local function image_enabled()
  return M.opts.image ~= nil and M.opts.image.enabled == true
end

local function image_filetype_enabled(filetype)
  local image = M.opts.image or {}
  for _, renderer in pairs(image.renderers or {}) do
    if list_contains(renderer.filetypes, filetype) then
      return true
    end
  end
  return false
end

local function renderer_for_source(kind, filetype)
  local fallback
  for renderer_kind, renderer in pairs((M.opts.image or {}).renderers or {}) do
    local source_kind = renderer.source_kind or renderer.scanner or renderer_kind
    if list_contains(renderer.filetypes, filetype) then
      return renderer_kind
    end
    if source_kind == kind then
      fallback = fallback or renderer_kind
    end
  end
  return fallback or (source_profiles[kind] and source_profiles[kind].renderer or nil)
end

local function setup_image()
  if not image_enabled() or M._image_setup_ran then
    return
  end

  local image_cfg = vim.deepcopy(M.opts.image or {})
  image_cfg.enabled = nil

  local service_binary = bundled_service_binary() or "typst-concealer-service"
  for _, renderer in pairs(image_cfg.renderers or {}) do
    if renderer.service_binary == nil then
      renderer.service_binary = service_binary
    end
  end

  require("math-conceal.image").setup(image_cfg)
  M._image_setup_ran = true
end

local function detected_filetype(bufnr, path)
  local filetype = vim.bo[bufnr].filetype
  if filetype ~= "" and not filetype:find("^snacks_") then
    return filetype
  end
  if path == "" then
    return filetype
  end
  local ok, detected = pcall(vim.filetype.match, { filename = path, buf = bufnr })
  return ok and detected or filetype
end

---Resolve the logical source carried by a buffer independently of its concrete filetype.
---@param bufnr integer?
---@param source string|table?
---@return MathConcealSource?
function M.resolve_source(bufnr, source)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  if type(source) == "string" then
    source = { kind = source }
  else
    source = vim.deepcopy(source or {})
  end

  local path = normalize_path(source.path or vim.api.nvim_buf_get_name(bufnr))
  local filetype = source.filetype or detected_filetype(bufnr, path)
  local kind = source.kind or filetype_source_kinds[filetype]
  if kind == nil then
    for renderer_kind, renderer in pairs((M.opts.image or {}).renderers or {}) do
      if list_contains(renderer.filetypes, filetype) then
        kind = renderer.source_kind or renderer.scanner or renderer_kind
        source.renderer = source.renderer or renderer_kind
        break
      end
    end
  end

  local profile = kind and source_profiles[kind] or nil
  if profile == nil then
    return nil
  end
  if filetype == nil or filetype == "" or filetype:find("^snacks_") then
    filetype = kind == "latex" and "tex" or kind
  end

  return {
    kind = kind,
    filetype = filetype,
    path = path,
    cwd = normalize_path(source.cwd or vim.uv.cwd()),
    root_lang = source.root_lang or profile.root_lang,
    conceal_lang = source.conceal_lang or profile.conceal_lang,
    renderer = source.renderer or renderer_for_source(kind, filetype),
  }
end

local function source_signature(source)
  return table.concat({
    source.kind,
    source.filetype,
    source.path,
    source.cwd,
    source.root_lang,
    source.conceal_lang,
    source.renderer or "",
  }, "\0")
end

local function setup_unicode_base()
  if unicode_base_setup then
    return
  end
  unicode_base_setup = true
  for name, val in pairs(M.opts.highlights) do
    vim.api.nvim_set_hl(M.opts.ns_id, name, val)
  end
  queries.load_queries()
end

local function ensure_unicode_language(source)
  setup_unicode_base()
  local lang = source.conceal_lang
  if M.queries[lang] == nil then
    M.files[lang] = queries.get_conceal_queries(lang, M.opts.conceal)
    M.queries[lang] = queries.read_query_files(M.files[lang])
    M.set_highlights(lang, M.queries[lang], "")
  end
  if render_languages_setup[lang] ~= true then
    render.setup(M.opts, lang)
    render_languages_setup[lang] = true
  end

  if source.root_lang == "markdown" and not markdown_highlights_setup then
    markdown_highlights_setup = true
    for _, markdown_lang in ipairs({ "markdown", "markdown_inline" }) do
      local key = "runtime:" .. markdown_lang
      M.files[key] = vim.treesitter.query.get_files(markdown_lang, "highlights")
      M.queries[key] = queries.read_query_files(M.files[key])
      M.set_highlights(markdown_lang, M.queries[key], source.filetype)
    end
  end
end

local function attach_unicode(bufnr, source)
  ensure_unicode_language(source)
  local extra_query = ""
  if source.kind == "latex" and source.filetype == "tex" then
    extra_query = queries.update_latex_queries(queries.get_preamble_conceal_map(bufnr))
  end
  return render.attach(bufnr, {
    conceal_lang = source.conceal_lang,
    root_lang = source.root_lang,
    extra_query_string = extra_query,
  })
end

local function binding_matches_source(binding, source)
  return binding ~= nil
    and binding.kind == source.renderer
    and binding.source_kind == source.kind
    and binding.filetype == source.filetype
    and normalize_path(binding.path) == source.path
end

local function requested_surfaces(state)
  local surfaces = { unicode = false, image = false }
  for _, request in pairs(state.owners) do
    surfaces.unicode = surfaces.unicode or request.surfaces.unicode == true
    surfaces.image = surfaces.image or request.surfaces.image == true
  end
  return surfaces
end

local mode_rank = { edit = 1, preview = 2, presentation = 3 }

local function reconcile_mode(state)
  local selected
  for _, request in pairs(state.owners) do
    if request.mode ~= nil and (selected == nil or mode_rank[request.mode] > mode_rank[selected]) then
      selected = request.mode
    end
  end

  if selected ~= nil then
    if state.saved_buffer_config == nil then
      state.saved_buffer_config = render.get_buffer_config(state.bufnr)
    end
    render.setup_buffer(state.bufnr, { mode = selected })
    state.mode_applied = true
    return false
  elseif state.mode_applied then
    render.setup_buffer(state.bufnr, state.saved_buffer_config)
    state.saved_buffer_config = nil
    state.mode_applied = false
    return true
  end
  return false
end

local function reconcile_surfaces(state)
  local wanted = requested_surfaces(state)
  if wanted.unicode and not state.unicode_attached then
    state.unicode_attached = attach_unicode(state.bufnr, state.source)
  elseif not wanted.unicode and state.unicode_attached then
    render.detach(state.bufnr)
    state.unicode_attached = false
  end

  if wanted.image and image_enabled() and state.source.renderer ~= nil then
    setup_image()
    local image = require("math-conceal.image")
    local binding = image.get_binding(state.bufnr)
    if binding == nil then
      state.image_owned = image.attach_buf(state.bufnr, {
        renderer = state.source.renderer,
        source = state.source,
      })
    elseif binding_matches_source(binding, state.source) and state.owners.filetype ~= nil then
      -- The image module may have attached first from its FileType autocmd.
      -- Adopt that matching automatic binding into the unified lifecycle.
      state.image_owned = true
    elseif not binding_matches_source(binding, state.source) then
      if not state.image_owned then
        error("math-conceal: buffer has a conflicting externally managed image binding", 3)
      end
      state.image_owned = image.attach_buf(state.bufnr, {
        renderer = state.source.renderer,
        source = state.source,
        replace = true,
      })
    end
  elseif state.image_owned then
    require("math-conceal.image").disable_buf(state.bufnr)
    state.image_owned = false
  end

  local restored_mode = reconcile_mode(state)
  if restored_mode and not wanted.unicode then
    render.detach(state.bufnr)
  end
  state.surfaces = wanted
end

local function teardown_state(state)
  local detach_render = state.unicode_attached or state.mode_applied
  if state.image_owned and M._image_setup_ran then
    require("math-conceal.image").disable_buf(state.bufnr)
    state.image_owned = false
  end
  state.owners = {}
  reconcile_mode(state)
  if detach_render then
    render.detach(state.bufnr)
  end
  state.unicode_attached = false
end

local function normalize_surfaces(source, opts, explicit_source)
  local requested = opts.surfaces or {}
  local unicode = requested.unicode
  if unicode == nil then
    unicode = explicit_source or list_contains(M.opts.ft, source.filetype)
  end
  local image = requested.image
  if image == nil then
    image = image_enabled() and source.renderer ~= nil
  end
  return { unicode = unicode == true, image = image == true }
end

---Attach configured conceal surfaces to a buffer using one logical source descriptor.
---@param bufnr integer?
---@param opts MathConcealAttachOptions?
---@return table attachment
function M.attach(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    error("math-conceal: invalid or unloaded buffer " .. tostring(bufnr), 2)
  end

  local explicit_source = opts.source ~= nil
  local source = M.resolve_source(bufnr, opts.source)
  if source == nil then
    error("math-conceal: unable to resolve a supported source for buffer " .. tostring(bufnr), 2)
  end

  local owner = opts.owner or {}
  local signature = source_signature(source)
  local state = attachments[bufnr]
  if state == nil then
    state = {
      bufnr = bufnr,
      source = source,
      source_signature = signature,
      owners = {},
      unicode_attached = false,
      image_owned = false,
      mode_applied = false,
    }
    attachments[bufnr] = state
  elseif state.source_signature ~= signature then
    for other_owner in pairs(state.owners) do
      if other_owner ~= owner then
        error("math-conceal: conflicting source attachments for buffer " .. tostring(bufnr), 2)
      end
    end
    teardown_state(state)
    state.source = source
    state.source_signature = signature
  end

  attachment_serial = attachment_serial + 1
  local token = attachment_serial
  state.owners[owner] = {
    token = token,
    surfaces = normalize_surfaces(source, opts, explicit_source),
    mode = opts.mode,
  }
  reconcile_surfaces(state)

  local handle = setmetatable({
    _math_conceal_attachment = true,
    bufnr = bufnr,
    owner = owner,
    token = token,
    source = vim.deepcopy(source),
    unicode = state.unicode_attached,
    image = state.surfaces.image and (state.image_owned or binding_matches_source(
      M._image_setup_ran and require("math-conceal.image").get_binding(bufnr) or nil,
      source
    )),
  }, attachment_handle_mt)
  return handle
end

---Detach one attachment handle/owner, or all unified attachments for a buffer.
---@param target table|integer?
---@param opts {owner:any?}?
---@return boolean
function M.detach(target, opts)
  opts = opts or {}
  local is_handle = type(target) == "table" and target._math_conceal_attachment == true
  local bufnr = normalize_bufnr(is_handle and target.bufnr or target)
  local state = attachments[bufnr]
  if state == nil then
    return false
  end

  local owner = is_handle and target.owner or opts.owner
  if owner ~= nil then
    local request = state.owners[owner]
    if request == nil or (is_handle and request.token ~= target.token) then
      return false
    end
    state.owners[owner] = nil
  else
    state.owners = {}
  end

  if next(state.owners) ~= nil then
    reconcile_surfaces(state)
    return true
  end

  teardown_state(state)
  attachments[bufnr] = nil
  return true
end

function attachment_handle_mt:detach()
  return M.detach(self)
end

function attachment_handle_mt:is_current()
  local state = attachments[self.bufnr]
  local request = state and state.owners[self.owner] or nil
  return request ~= nil and request.token == self.token
end

---Refresh the surfaces owned by a current attachment without changing its source.
---@param target table|integer?
---@param opts MathConcealAttachSurfaces?
---@return boolean
function M.refresh(target, opts)
  opts = opts or {}
  local is_handle = type(target) == "table" and target._math_conceal_attachment == true
  local bufnr = normalize_bufnr(is_handle and target.bufnr or target)
  local state = attachments[bufnr]
  if state == nil then
    return false
  end
  if is_handle then
    local request = state.owners[target.owner]
    if request == nil or request.token ~= target.token then
      return false
    end
  end

  if opts.unicode ~= false and state.unicode_attached then
    render.detach(bufnr)
    state.unicode_attached = false
  end
  if opts.image == true and state.image_owned and M._image_setup_ran then
    state.image_owned = require("math-conceal.image").attach_buf(bufnr, {
      renderer = state.source.renderer,
      source = state.source,
      replace = true,
    })
  end
  reconcile_surfaces(state)
  return true
end

function attachment_handle_mt:refresh(opts)
  return M.refresh(self, opts)
end

---@param bufnr integer?
---@return table?
function M.get_attachment(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = attachments[bufnr]
  if state == nil then
    return nil
  end
  local binding = M._image_setup_ran and require("math-conceal.image").get_binding(bufnr) or nil
  return {
    source = vim.deepcopy(state.source),
    owner_count = vim.tbl_count(state.owners),
    unicode = state.unicode_attached,
    image = binding_matches_source(binding, state.source),
    mode = render.get_buffer_config(bufnr).mode,
  }
end

vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
  group = attachment_augroup,
  callback = function(ev)
    M.detach(ev.buf)
  end,
})

---set up
---@param opts MathConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  window_options.setup(M.opts.opt)
  render.set_default_buffer_config(M.opts.buffer)
  setup_image()

  local snacks_opts = (M.opts.integrations or {}).snacks
  local ok_snacks, snacks = pcall(require, "math-conceal.integrations.snacks")
  if ok_snacks then
    if snacks_opts == false or (type(snacks_opts) == "table" and snacks_opts.enabled == false) then
      snacks.teardown()
    else
      pcall(snacks.setup, type(snacks_opts) == "table" and snacks_opts or {})
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      local filetype = vim.bo[bufnr].filetype
      if filetype ~= "" and (list_contains(M.opts.ft, filetype) or image_filetype_enabled(filetype)) then
        M.set(filetype, bufnr)
      end
    end
  end
end

---Configure ASCII/Unicode conceal behavior for one buffer.
---Examples:
---  require("math-conceal").setup_buffer({ mode = "preview" })
---  require("math-conceal").setup_buffer({ mode = "presentation" })
---  require("math-conceal").setup_buffer(bufnr, { mode = "edit" })
---@param bufnr integer|MathConcealBufferOptions?
---@param opts MathConcealBufferOptions?
---@return MathConcealBufferOptions
function M.setup_buffer(bufnr, opts)
  return render.setup_buffer(bufnr, opts)
end

---Return the effective ASCII/Unicode conceal config for one buffer.
---@param bufnr integer?
---@return MathConcealBufferOptions
function M.get_buffer_config(bufnr)
  return render.get_buffer_config(bufnr)
end

---Return true when one buffer is in presentation mode.
---@param bufnr integer?
---@return boolean
function M.is_presentation_mode(bufnr)
  return render.is_presentation_mode(bufnr)
end

---Compatibility entry point used by the bundled ftplugins.
---@param filetype string?
---@param bufnr integer?
function M.set(filetype, bufnr)
  bufnr = normalize_bufnr(bufnr)
  filetype = filetype or vim.bo[bufnr].filetype
  local unicode = list_contains(M.opts.ft, filetype)
  local image = image_enabled()
    and (M.opts.image or {}).enabled_by_default ~= false
    and image_filetype_enabled(filetype)
  if not unicode and not image then
    M.detach(bufnr, { owner = "filetype" })
    return
  end

  local source = M.resolve_source(bufnr, { filetype = filetype })
  if source == nil then
    return
  end
  local attachment = M.attach(bufnr, {
    source = source,
    surfaces = { unicode = unicode, image = image },
    owner = "filetype",
  })

  if filetype == "tex" then
    M.opts.augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
    pcall(vim.api.nvim_clear_autocmds, {
      group = M.opts.augroup_id,
      buffer = bufnr,
      event = "BufWritePost",
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = M.opts.augroup_id,
      buffer = bufnr,
      callback = function(args)
        M.refresh(args.buf, { unicode = true, image = false })
      end,
    })
  end

  return attachment
end

---Compatibility entry point for attaching only ASCII/Unicode conceal.
---@param filetype string
---@param bufnr integer?
function M.set_hl(filetype, bufnr)
  bufnr = normalize_bufnr(bufnr)
  local source = M.resolve_source(bufnr, { filetype = filetype })
  if source == nil then
    return
  end
  return M.attach(bufnr, {
    source = source,
    surfaces = { unicode = true, image = false },
    owner = "unicode-legacy",
  })
end

---set highlights for lang.
---if filetype == 'tex', update queries for preamble
---@param lang string
---@param code string?
---@param filetype string?
function M.set_highlights(lang, code, filetype)
  filetype = filetype or vim.bo.filetype
  code = code or ""
  local extra_code = ""

  if filetype == "tex" then
    local conceal_map = queries.get_preamble_conceal_map()
    extra_code = queries.update_latex_queries(conceal_map)
    code = code .. "\n" .. extra_code
    render.update_extra_query(lang, extra_code)
  end

  vim.treesitter.query.set(lang, "highlights", queries.strip_conceal_directives(code))
end

return M
