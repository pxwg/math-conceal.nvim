local state = require("math-conceal.image.state")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function bucket_for(bufnr)
  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  return state.render_diagnostics[bufnr]
end

local function append_bucket(items, bucket)
  local node_ids = vim.tbl_keys(bucket or {})
  table.sort(node_ids)
  for _, node_id in ipairs(node_ids) do
    for _, item in ipairs(bucket[node_id] or {}) do
      items[#items + 1] = item
    end
  end
end

function M.rebuild(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bucket = state.render_diagnostics[bufnr] or {}
  local items = {}
  append_bucket(items, bucket.flow_by_node)
  append_bucket(items, bucket.formula_by_node)

  vim.schedule(function()
    vim.fn.setqflist({}, "r", {
      title = "math-conceal.image: "
        .. (vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.api.nvim_buf_get_name(bufnr) or ("buf:" .. bufnr)),
      items = items,
    })
  end)
end

function M.set_items(bufnr, bucket_name, node_id, items)
  bufnr = normalize_bufnr(bufnr)
  local bucket = bucket_for(bufnr)
  bucket[bucket_name] = bucket[bucket_name] or {}
  if type(items) ~= "table" or #items == 0 then
    bucket[bucket_name][node_id] = nil
  else
    bucket[bucket_name][node_id] = items
  end
  M.rebuild(bufnr)
end

return M
