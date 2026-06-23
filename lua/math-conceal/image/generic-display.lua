local state = require("math-conceal.image.state")
local surface = require("math-conceal.image.surface")

local M = {}

local function clear_aux(projection)
  if projection.aux_extmark_ids == nil or not vim.api.nvim_buf_is_valid(projection.bufnr) then
    projection.aux_extmark_ids = nil
    return
  end

  for _, id in ipairs(projection.aux_extmark_ids) do
    pcall(vim.api.nvim_buf_del_extmark, projection.bufnr, state.aux_ns, id)
  end
  projection.aux_extmark_ids = nil
end

local function slice_lines(lines, first, last)
  local out = {}
  if first == nil or last == nil or first > last then
    return out
  end
  for idx = first, math.min(last, #lines) do
    out[#out + 1] = lines[idx]
  end
  return out
end

local function line_extmark_opts(bufnr, row, virt_text, virt_lines)
  local opts = {
    virt_text = virt_text,
    virt_text_pos = "overlay",
    conceal = "",
    end_col = surface.line_len(bufnr, row),
    end_row = row,
    invalidate = true,
    priority = 220,
  }
  if #virt_lines > 0 then
    opts.virt_lines = virt_lines
    opts.virt_lines_overflow = "trunc"
  end
  return opts
end

function M.reveal(projection)
  clear_aux(projection)
  if projection.display_extmark_id ~= nil and vim.api.nvim_buf_is_valid(projection.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, projection.bufnr, state.display_ns, projection.display_extmark_id)
  end
  projection.display_extmark_id = nil
  projection.revealed = true
end

function M.clear(projection)
  M.reveal(projection)
end

function M.show(projection, track, asset, config)
  if track == nil or asset == nil or not vim.api.nvim_buf_is_valid(projection.bufnr) then
    return false
  end

  clear_aux(projection)
  local start_row, start_col, end_row, end_col = surface.display_range(track)
  local cols, rows = surface.clamp_cells(asset.cols, asset.rows)
  asset.cols = cols
  asset.rows = rows
  local hl = state.image_hl_group(asset.image_id)

  local opts = {
    id = projection.display_extmark_id,
    end_row = end_row,
    end_col = end_col,
    invalidate = true,
    priority = 220,
    conceal = "",
  }

  if track.source_display_kind == "block" then
    local pad = surface.block_left_pad_cols(projection.bufnr, track, cols)
    local pad_text = pad > 0 and string.rep(" ", pad) or ""
    local function row_chunks(row)
      return { { pad_text, "" }, { surface.placeholder_row(row, cols), hl } }
    end

    local image_lines = {}
    for row = 1, rows do
      image_lines[row] = row_chunks(row)
    end

    opts.virt_text = { { "" } }
    opts.virt_text_pos = "overlay"
    projection.display_extmark_id =
      vim.api.nvim_buf_set_extmark(projection.bufnr, state.display_ns, start_row, start_col, opts)

    local aux_ids = {}
    local has_end_landing = end_row > start_row and rows > 1
    local start_virt_lines = has_end_landing and slice_lines(image_lines, 2, rows - 1)
      or slice_lines(image_lines, 2, rows)

    aux_ids[#aux_ids + 1] = vim.api.nvim_buf_set_extmark(
      projection.bufnr,
      state.aux_ns,
      start_row,
      0,
      line_extmark_opts(projection.bufnr, start_row, image_lines[1], start_virt_lines)
    )

    if has_end_landing then
      aux_ids[#aux_ids + 1] = vim.api.nvim_buf_set_extmark(
        projection.bufnr,
        state.aux_ns,
        end_row,
        0,
        line_extmark_opts(projection.bufnr, end_row, image_lines[rows], {})
      )
    end

    for row = start_row, end_row do
      local is_landing = row == start_row or (has_end_landing and row == end_row)
      if not is_landing then
        aux_ids[#aux_ids + 1] = vim.api.nvim_buf_set_extmark(projection.bufnr, state.aux_ns, row, 0, {
          conceal_lines = "",
          end_row = row,
          invalidate = true,
          priority = 220,
        })
      end
    end

    projection.aux_extmark_ids = aux_ids
    projection.revealed = false
    return true
  else
    opts.virt_text = { { surface.placeholder_row(1, cols), hl } }
    opts.virt_text_pos = "inline"
  end

  projection.display_extmark_id =
    vim.api.nvim_buf_set_extmark(projection.bufnr, state.display_ns, start_row, start_col, opts)
  projection.revealed = false
  return true
end

return M
