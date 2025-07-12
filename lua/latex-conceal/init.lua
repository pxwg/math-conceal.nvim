local M = {}
local highlights = require("latex-conceal.highlights")

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class LaTeXConcealOptions
--- @field enabled boolean: Enable or disable LaTeX conceal. Default is true.
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable LaTeX conceal. Default is {"tex", "latex", "markdown", "typst"}.

-- Default options
--- @type LaTeXConcealOptions
local default_opts = {
  enabled = true,
  conceal = {
    "greek",
    -- "script",
    "math",
    "font",
    "delim",
    "phy",
  },
  ft = { "tex", "latex", "markdown", "typst" },
}
local autocmd = require("latex-conceal.autocmd")

function M.setup(opts)
  highlights.set_highlights()
  M.opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  if M.opts.enabled then
    local success = require("utils.latex_conceal").initialize()
    if not success then
      vim.notify("LaTeX conceal initialization failed", vim.log.levels.WARN)
    else
      autocmd.subscribe_autocmd(M.opts)
    end
  end
end

return M
