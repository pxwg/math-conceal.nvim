local fold_grid = require("math-conceal.image.placement.fold-grid")

local M = {}

fold_grid.setup()

function M.sync(bufnr, intent)
  return fold_grid.sync(bufnr, intent)
end

function M.close_key(bufnr, key)
  return fold_grid.close_key(bufnr, key)
end

function M.close_all(bufnr)
  return fold_grid.close_all(bufnr)
end

function M.reconcile(bufnr, keep_keys)
  return fold_grid.reconcile(bufnr, keep_keys)
end

function M.refresh_buf(bufnr)
  return fold_grid.refresh_buf(bufnr)
end

function M.batch(fn)
  return fold_grid.batch(fn)
end

function M.foldexpr(lnum)
  return fold_grid.foldexpr(lnum)
end

function M.foldtext()
  return fold_grid.foldtext()
end

function M.layout_rows(source_start_row, source_end_row, image_rows)
  return fold_grid.layout_rows(source_start_row, source_end_row, image_rows)
end

function M._state()
  return fold_grid._state()
end

return M
