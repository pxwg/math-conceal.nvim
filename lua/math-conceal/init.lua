--- init.lua - Math Conceal plugin entry point
--- Simplified configuration and setup
local M = {}

local loader = require("math-conceal.loader")
local render = require("math-conceal.render")

--- @class MathConcealOptions
--- @field conceal string[]? Conceal types to enable (e.g., "greek", "script", "math", "font", "delim", "phy")
--- @field ft string[]? Filetypes to enable conceal
--- @field ns_id integer? Namespace ID for highlights
--- @field highlights table<string, table<string, string>>? Highlight group definitions

--- @type MathConcealOptions
local default_opts = {
  conceal = { "greek", "script", "math", "font", "delim", "phy" },
  ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
  ns_id = 0,
  highlights = {
    ["@_cmd"] = { link = "@conceal" },
    ["@cmd"] = { link = "@conceal" },
    ["@func"] = { link = "@conceal" },
    ["@font_letter"] = { link = "@conceal" },
    ["@sub"] = { link = "@conceal" },
    ["@sub_ident"] = { link = "@conceal" },
    ["@sub_letter"] = { link = "@conceal" },
    ["@sub_number"] = { link = "@conceal" },
    ["@sup"] = { link = "@conceal" },
    ["@sup_ident"] = { link = "@conceal" },
    ["@sup_letter"] = { link = "@conceal" },
    ["@sup_number"] = { link = "@conceal" },
    ["@symbol"] = { link = "@conceal" },
    ["@typ_font_name"] = { link = "@conceal" },
    ["@typ_greek_symbol"] = { link = "@conceal" },
    ["@typ_inline_dollar"] = { link = "@conceal" },
    ["@typ_math_delim"] = { link = "@conceal" },
    ["@typ_math_font"] = { link = "@conceal" },
    ["@typ_math_symbol"] = { link = "@conceal" },
    ["@typ_phy_symbol"] = { link = "@conceal" },
    ["@conceal"] = { link = "@conceal" },
    ["@open1"] = { link = "@conceal" },
    ["@open2"] = { link = "@conceal" },
    ["@close1"] = { link = "@conceal" },
    ["@close2"] = { link = "@conceal" },
    ["@punctuation"] = { link = "@conceal" },
    ["@left_paren"] = { link = "@conceal" },
    ["@right_paren"] = { link = "@conceal" },
    ["@tex_greek"] = { link = "@conceal" },
    ["@tex_font_name"] = { link = "@conceal" },
  },
}

--- @type MathConcealOptions
M.opts = vim.deepcopy(default_opts)

-- Track if we've done initial setup
local initialized = false

--- Ensure the plugin is initialized (lazy init on first use)
local function ensure_initialized()
  if initialized then
    return
  end
  initialized = true

  -- Setup loader with current options
  loader.setup({
    conceal = M.opts.conceal,
    ft = M.opts.ft,
    ns_id = M.opts.ns_id,
    highlights = M.opts.highlights,
  })
end

--- Setup the math-conceal plugin
--- @param opts MathConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  initialized = false -- Reset so next ensure_initialized() uses new opts
  ensure_initialized()
end

--- Enable conceal for current buffer
--- Called from ftplugin files
--- @param filetype string?
function M.set(filetype)
  filetype = filetype or vim.bo.filetype

  -- Lazy initialize on first use
  ensure_initialized()

  -- Check if this filetype is supported
  if not loader.is_supported_filetype(filetype) then
    return
  end

  -- Attach conceal to current buffer
  loader.attach(0, filetype)
end

--- Alias for backward compatibility
--- @param filetype string
function M.set_hl(filetype)
  M.set(filetype)
end

--- Refresh conceal for current buffer
function M.refresh()
  loader.refresh(0)
end

--- Disable conceal for current buffer
function M.disable()
  loader.detach(0)
end

--- Check if conceal is active for current buffer
--- @return boolean
function M.is_active()
  return render.is_attached(0)
end

--- Get currently active languages for the buffer
--- @return string[]
function M.get_active_langs()
  return render.get_registered_langs(0)
end

--- Manually register a custom query for a buffer
--- Useful for extending conceal behavior
--- @param buf integer Buffer number (0 for current)
--- @param lang string Tree-sitter language
--- @param query_string string SCM query string
--- @return boolean success
function M.register_custom_query(buf, lang, query_string)
  return render.register_query(buf, lang, query_string)
end

--- Invalidate query cache (call when query files change)
--- @param lang string? Language to invalidate (nil for all)
function M.invalidate_cache(lang)
  loader.invalidate_cache(lang)
end

return M
