local grid = require("math-conceal.image.grid")
local state = require("math-conceal.image.state")

local M = {}

local clamp_cells = grid.clamp
local placeholder_row = grid.placeholder_row

function M.placeholder_row(row, cols)
  return placeholder_row(row, cols)
end

local function is_code_block(track)
  if track == nil or (track.object_kind or track.node_type) ~= "code" then
    return false
  end
  local facts = track.source_facts or {}
  local equation = track.equation or track.object or {}
  return track.source_display_kind == "block"
    or facts.layout_role == "block"
    or equation.display_role == "block"
    or facts.render_policy == "block"
    or facts.render_policy == "block_constrained"
end

local function block_left_pad_cols(bufnr, track, cols)
  if is_code_block(track) then
    return 0
  end
  local win_width = state.visible_window_width(bufnr)
  if cols < win_width then
    return math.floor((win_width - cols) / 2)
  end
  return 0
end

function M.block_left_pad_cols(bufnr, track, cols)
  return block_left_pad_cols(bufnr, track, cols)
end

local function code_block_layout_config(config)
  local renderers = config and config.renderers or nil
  local typst = renderers and renderers.typst or nil
  return (typst and typst.code_block) or {}
end

local function code_block_max_cols(track, config)
  local cfg = code_block_layout_config(config)
  local pad_cols = math.max(0, tonumber(cfg.padding_cols) or 0)
  local right_pad_cols = math.max(0, tonumber(cfg.right_padding_cols) or 1)
  return math.max(1, state.visible_text_width(track.bufnr) - 2 * pad_cols - right_pad_cols)
end

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function clamp_range(bufnr, start_row, start_col, end_row, end_col)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return 0, 0, 0, 0
  end

  start_row = math.max(0, math.min(start_row, line_count - 1))
  end_row = math.max(start_row, math.min(end_row, line_count - 1))
  start_col = math.max(0, math.min(start_col, line_len(bufnr, start_row)))
  end_col = math.max(0, math.min(end_col, line_len(bufnr, end_row)))
  if start_row == end_row and end_col < start_col then
    end_col = start_col
  end
  return start_row, start_col, end_row, end_col
end

local function display_range(track)
  if track.source_display_kind == "block" and track.render_whole_line == true then
    return clamp_range(track.bufnr, track.row, 0, track.end_row, line_len(track.bufnr, track.end_row))
  end
  return clamp_range(track.bufnr, track.row, track.col, track.end_row, track.end_col)
end

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
    end_col = line_len(bufnr, row),
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

function M.cell_dimensions(track, width_px, height_px, config)
  local source_rows = track.source_rows or math.max(1, track.end_row - track.row + 1)
  local cols, rows = grid.natural_dimensions(track.source_display_kind, source_rows, width_px, height_px)

  if track.source_display_kind == "block" then
    local max_cols
    if is_code_block(track) then
      max_cols = code_block_max_cols(track, config)
    else
      max_cols =
        math.max(1, state.visible_window_width(track.bufnr) - 2 * ((config and config.block_padding_cols) or 0))
    end
    cols = math.min(cols, max_cols)
  end

  return clamp_cells(cols, rows)
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
  local start_row, start_col, end_row, end_col = display_range(track)
  local cols, rows = clamp_cells(asset.cols, asset.rows)
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
    local pad = block_left_pad_cols(projection.bufnr, track, cols)
    local pad_text = pad > 0 and string.rep(" ", pad) or ""
    local function row_chunks(row)
      return { { pad_text, "" }, { placeholder_row(row, cols), hl } }
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
    opts.virt_text = { { placeholder_row(1, cols), hl } }
    opts.virt_text_pos = "inline"
  end

  projection.display_extmark_id =
    vim.api.nvim_buf_set_extmark(projection.bufnr, state.display_ns, start_row, start_col, opts)
  projection.revealed = false
  return true
end

return M
