local M = {}

local ns = vim.api.nvim_create_namespace("math-conceal.image.tracker.debug")

local function marker(track)
  if track.state == "dirty" then
    return { { "⟦" .. track.id .. ":" .. track.rev .. " dirty⟧", "DiagnosticVirtualTextError" } }
  end
  return { { "⟦" .. track.id .. ":" .. track.rev .. "⟧", "DiagnosticVirtualTextInfo" } }
end

---@param bufnr integer
function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
end

---@param bufnr integer
---@param tracks table[]
---@param opts table?
function M.refresh(bufnr, tracks, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.clear(bufnr)
  if opts.enabled == false then
    return
  end

  for _, track in ipairs(tracks or {}) do
    if track.state ~= "retired" and not track.invalid then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, track.row, track.col, {
        id = track.id,
        end_row = track.end_row,
        end_col = track.end_col,
        virt_text = marker(track),
        virt_text_pos = "inline",
        right_gravity = true,
        end_right_gravity = false,
        undo_restore = true,
        invalidate = true,
        priority = 200,
      })
    end
  end
end

return M
