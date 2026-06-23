local session = require("math-conceal.image.session")
local state = require("math-conceal.image.state")

local M = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function close_timer(preview)
  if preview ~= nil and preview.timer ~= nil then
    preview.timer:stop()
    if not preview.timer:is_closing() then
      preview.timer:close()
    end
    preview.timer = nil
  end
end

local function reset_preview(preview)
  if preview == nil then
    return
  end
  preview.extmark_id = nil
  preview.visible_asset = nil
  preview.pending_key = nil
  preview.render_key = nil
  preview.track_key = nil
  preview.source_range = nil
  preview.handoff_key = nil
end

function M.clear(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local bs = state.get_buf_state(bufnr)
  local preview = bs.live_preview
  close_timer(preview)
  session.cancel_live_preview(bufnr)
  reset_preview(preview)
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.preview_ns, 0, -1)
  end
end

local function has_preview_state(bufnr)
  local bs = state.get_buf_state(normalize_bufnr(bufnr))
  local preview = bs.live_preview
  return preview ~= nil
    and (
      preview.extmark_id ~= nil
      or preview.visible_asset ~= nil
      or preview.pending_key ~= nil
      or preview.timer ~= nil
    )
end

function M.sync(bufnr)
  if has_preview_state(bufnr) then
    M.clear(bufnr)
  end
end

function M.schedule(bufnr)
  if has_preview_state(bufnr) then
    M.clear(bufnr)
  end
end

function M.refresh(bufnr)
  if has_preview_state(bufnr) then
    M.clear(bufnr)
  end
end

function M.handle_service_response(_bufnr, _resp, _meta)
  -- Live Preview Projection is intentionally disconnected during the Snacks
  -- main-buffer placement migration. Late service responses are ignored.
end

function M.detach(bufnr)
  M.clear(bufnr)
end

return M
