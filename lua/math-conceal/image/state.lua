local M = {}

M.display_ns = vim.api.nvim_create_namespace("math-conceal.image.display")
M.aux_ns = vim.api.nvim_create_namespace("math-conceal.image.display.aux")
M.preview_ns = vim.api.nvim_create_namespace("math-conceal.image.preview")

M._cell_px_w = nil
M._cell_px_h = nil
M._render_ppi = nil

M.buffers = {}
M.render_diagnostics = {}
M.image_id_to_bufnr = {}

M.pid = vim.fn.getpid() % 256
M.next_image_counter = 1

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function default(val, fallback)
  if val == nil then
    return fallback
  end
  return val
end

function M.get_buf_state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if M.buffers[bufnr] == nil then
    M.buffers[bufnr] = {
      projections = {},
      projections_by_track_id = {},
      live_preview = {
        extmark_id = nil,
        visible_asset = nil,
        pending_key = nil,
        render_key = nil,
        track_key = nil,
        source_range = nil,
        vertical = "above",
        timer = nil,
      },
      context = nil,
      pending_batches = {},
      cursor_revealed = {},
      context_rev = 0,
      context_signature = nil,
    }
  end
  return M.buffers[bufnr]
end

function M.drop_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  M.buffers[bufnr] = nil
  M.render_diagnostics[bufnr] = nil
end

function M.allocate_image_id(bufnr)
  for _ = 1, 0xFFFF do
    local counter = M.next_image_counter
    M.next_image_counter = M.next_image_counter + 1
    if M.next_image_counter > 0xFFFF then
      M.next_image_counter = 1
    end

    local id = M.pid * 0x10000 + counter
    if M.image_id_to_bufnr[id] == nil then
      M.image_id_to_bufnr[id] = bufnr
      return id
    end
  end

  error("math-conceal.image exhausted kitty placeholder image ids")
end

function M.release_image_id(image_id)
  M.image_id_to_bufnr[image_id] = nil
end

function M.image_hl_group(image_id)
  local hl = "math-conceal-image-id-" .. tostring(image_id)
  vim.api.nvim_set_hl(0, hl, { fg = string.format("#%06X", image_id), nocombine = true })
  return hl
end

function M.visible_window_width(bufnr)
  local wins = vim.fn.win_findbuf(bufnr)
  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) then
      return vim.api.nvim_win_get_width(winid)
    end
  end
  return vim.o.columns
end

function M.refresh_cell_px_size(config)
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return false
  end

  pcall(
    ffi.cdef,
    [[
    typedef struct { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; } math_conceal_winsize_t;
    int ioctl(int fd, unsigned long request, ...);
  ]]
  )

  local request = vim.fn.has("mac") == 1 and 0x40087468 or 0x5413
  local ws = ffi.new("math_conceal_winsize_t")
  local old_w, old_h, old_ppi = M._cell_px_w, M._cell_px_h, M._render_ppi
  if ffi.C.ioctl(1, request, ws) == 0 and ws.ws_xpixel > 0 and ws.ws_col > 0 then
    M._cell_px_w = ws.ws_xpixel / ws.ws_col
    M._cell_px_h = ws.ws_ypixel / ws.ws_row
    local baseline = default(config and config.math_baseline_pt, 11)
    M._render_ppi = math.max(72, math.floor(M._cell_px_h * 72 / baseline))
  end
  return old_w ~= M._cell_px_w or old_h ~= M._cell_px_h or old_ppi ~= M._render_ppi
end

function M.render_ppi(config)
  return M._render_ppi or default(config and config.ppi, 300)
end

function M.cell_size()
  return M._cell_px_w, M._cell_px_h
end

return M
