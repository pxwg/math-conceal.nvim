--- Typst source adapter metadata.

local M = {}

function M.render_viewport()
  return {
    kind = "buffer",
  }
end

function M.render_policy()
  return {
    kind = "buffer",
  }
end

return M
