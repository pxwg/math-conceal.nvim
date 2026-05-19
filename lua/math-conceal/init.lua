local queries = require("math-conceal.query")
local render = require("math-conceal.render")
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
    depth = 90,
    ns_id = 0,
    image = {
      enabled = false,
      filetypes = { "typst" },
    },
    highlights = {
      ["@_env"] = { link = "@conceal", default = true },
      ["@_frac_name"] = { link = "@conceal", default = true },
      ["@_func_name"] = { link = "@conceal", default = true },
      ["@_line"] = { link = "@conceal", default = true },
      ["@abs_name"] = { link = "@conceal", default = true },
      ["@close_paren"] = { link = "@conceal", default = true },
      ["@cmd"] = { link = "@conceal", default = true },
      ["@comma"] = { link = "@conceal", default = true },
      ["@conceal"] = { link = "Conceal", default = true },
      ["@conceal_dollar"] = { link = "@conceal", default = true },
      ["@content"] = { link = "@conceal", default = true },
      ["@first_letter"] = { link = "@conceal", default = true },
      ["@font_letter"] = { link = "@conceal", default = true },
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
      ["@sub_letter"] = { link = "@conceal", default = true },
      ["@sub_object"] = { link = "@conceal", default = true },
      ["@sub_symbol"] = { link = "@conceal", default = true },
      ["@sup_letter"] = { link = "@conceal", default = true },
      ["@sup_object"] = { link = "@conceal", default = true },
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
    },
  },
}

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class MathConcealOptions
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable conceal
--- @field depth integer
--- @field augroup_id integer?
--- @field ns_id integer
--- @field highlights table<string, table<string, string>>
--- @field image MathConcealImageOptions?

--- @class MathConcealImageOptions
--- @field enabled boolean?: Enable image conceal. Default false.
--- @field filetypes string[]?: Filetypes managed by image conceal. Default { "typst" }.
--- Other fields are passed through to `math-conceal.image`.

local function plugin_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    local init_path = source:sub(2)
    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(init_path)))
  end
end

local function bundled_service_binary()
  local root = plugin_root()
  if not root then
    return nil
  end
  local exe = vim.fn.has("win32") == 1 and "typst-concealer-service.exe" or "typst-concealer-service"
  local path = table.concat({ root, "service", "target", "release", exe }, "/")
  if vim.uv.fs_stat(path) ~= nil then
    return path
  end
end

local function image_enabled()
  return M.opts.image ~= nil and M.opts.image.enabled == true
end

local function image_filetype_enabled(filetype)
  local image = M.opts.image or {}
  for _, ft in ipairs(image.filetypes or {}) do
    if ft == filetype then
      return true
    end
  end
  return false
end

local function setup_image()
  if not image_enabled() or M._image_setup_ran then
    return
  end

  local image_cfg = vim.deepcopy(M.opts.image or {})
  image_cfg.enabled = nil
  image_cfg.filetypes = nil
  if image_cfg.service_binary == nil then
    image_cfg.service_binary = bundled_service_binary() or "typst-concealer-service"
  end

  require("math-conceal.image").setup(image_cfg)
  M._image_setup_ran = true
end

local function set_image(filetype)
  if not image_enabled() or not image_filetype_enabled(filetype) then
    return
  end

  setup_image()
  local image = require("math-conceal.image")
  local bufnr = vim.api.nvim_get_current_buf()
  if image.config.enabled_by_default and image.is_supported_bufnr(bufnr) and image.is_render_allowed(bufnr) then
    image.enable_buf(bufnr)
  end
end

---set up
---@param opts MathConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  setup_image()
end

---check if `filetype` is in `M.opts.ft`.
---if true, call `set_hl`
---@param filetype string?
function M.set(filetype)
  filetype = filetype or vim.bo.filetype
  for _, ft in ipairs(M.opts.ft) do
    if ft == filetype then
      M.set_hl(filetype)
    end
  end
  set_image(filetype)
end

local function restart_treesitter(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  pcall(vim.treesitter.stop, bufnr)
  pcall(vim.treesitter.start, bufnr)
end

---do some prepare work, then call `set_highlights`
---@param filetype string
function M.set_hl(filetype)
  vim.opt_local.conceallevel = 2
  vim.opt_local.concealcursor = "nci"

  -- set typst math conceal for typst
  -- and set latex math conceal for all other filetypes.
  ---@type "typst" | "latex"
  local lang = filetype == "typst" and filetype or "latex"
  --- first run
  if #M.queries == 0 then
    for name, val in pairs(M.opts.highlights) do
      vim.api.nvim_set_hl(M.opts.ns_id, name, val)
    end
    queries.load_queries()
    render.setup(M.opts, lang)
  end

  --- after editing preamble and save, reset highlights
  if filetype == "tex" then
    M.opts.augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = M.opts.augroup_id,
      buffer = 0,
      callback = function(args)
        M.set_highlights("latex", M.queries.latex, "tex")
        restart_treesitter(args.buf)
        render.attach(args.buf, "latex")
      end,
    })
  end

  ---always reset highlights for tex due to preamble
  local should_set_hl = filetype == "tex"
  -- if haven't set highlights, must set highlights
  if M.queries[lang] == nil then
    M.files[lang] = queries.get_conceal_queries(lang, M.opts.conceal)
    M.queries[lang] = queries.read_query_files(M.files[lang])
    should_set_hl = true
  end
  if should_set_hl then
    M.set_highlights(lang, M.queries[lang], filetype)
  end

  if filetype == "markdown" then
    for _, markdown_lang in ipairs({ "markdown", "markdown_inline" }) do
      local key = "runtime:" .. markdown_lang
      if M.queries[key] == nil then
        M.files[key] = vim.treesitter.query.get_files(markdown_lang, "highlights")
        M.queries[key] = queries.read_query_files(M.files[key])
      end
      M.set_highlights(markdown_lang, M.queries[key], filetype)
    end
  end

  restart_treesitter(vim.api.nvim_get_current_buf())

  -- Always try to attach render to current buffer
  render.attach(vim.api.nvim_get_current_buf(), lang)
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
