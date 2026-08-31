local M = {}

function M.inspect()
  return {
    nvim_011 = vim.fn.has("nvim-0.11") == 1,
    nvim_version = vim.version(),
    apis = {
      nvim__ns_set = type(vim.api.nvim__ns_set) == "function",
      nvim_win_text_height = type(vim.api.nvim_win_text_height) == "function",
    },
  }
end

function M.assert_supported()
  local report = M.inspect()
  local missing = {}
  if not report.nvim_011 then
    missing[#missing + 1] = "Neovim 0.11 or newer"
  end
  for name, available in pairs(report.apis) do
    if not available then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    table.sort(missing)
    error("math-conceal image rendering requires " .. table.concat(missing, ", "), 2)
  end
  if not require("math-conceal.image.placement").available() then
    error("math-conceal image rendering could not create a window-scoped placement namespace", 2)
  end
  return report
end

return M
