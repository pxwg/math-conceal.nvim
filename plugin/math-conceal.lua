if vim.g.loaded_math_conceal == 1 then
  return
end
vim.g.loaded_math_conceal = 1

-- Attach default filetypes even without an explicit setup() call.
require("math-conceal")._register_filetype_hook()
