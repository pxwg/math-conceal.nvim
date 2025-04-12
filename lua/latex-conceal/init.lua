local M = {}

--- @type NoteTreeOpts

-- Default options
local default_opts = {
  enabled = true,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  if M.opts.enabled then
    local success = require("utils.latex_conceal").initialize()
    if not success then
      vim.notify("LaTeX conceal initialization failed", vim.log.levels.WARN)
    end
  end
end

return M
