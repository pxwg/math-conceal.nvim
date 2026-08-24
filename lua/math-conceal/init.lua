local M = {
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
            exclude = {},
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
--- @field mitex_preamble string?: LaTeX macro prelude prepended to each Markdown MiTeX formula.
--- @field mitex_preamble_file string|fun(ctx: table): string?: File containing a LaTeX macro prelude for Markdown MiTeX formulas.
--- @field code_render table?: Typst code rendering policy. `allow` adds names; `exclude` removes names from the effective allowlist and takes precedence.
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

---Configure the plugin. Merges user options into the plugin defaults. The runtime
---logic lives in `math-conceal.nvim` and is loaded on demand from there; this
---module only owns configuration, so a bare `require("math-conceal")` plus
---`setup()` never loads the heavy `query`/`render`/`window-options` modules.
---@param opts MathConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
