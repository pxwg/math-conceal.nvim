local codes = require("math-conceal.image.kitty-codes")
local state = require("math-conceal.image.state")

local M = {}

local function capacity()
  return math.max(1, #codes.diacritics - 1)
end

local function clamp_cells(cols, rows)
  local cap = capacity()
  cols = math.max(1, math.min(cap, math.floor(tonumber(cols) or 1)))
  rows = math.max(1, math.min(cap, math.floor(tonumber(rows) or 1)))
  return cols, rows
end

local function placeholder_row(row, cols)
  row = math.max(1, math.min(#codes.diacritics, row))
  local line = {}
  for col = 0, cols - 1 do
    line[#line + 1] = codes.placeholder .. codes.diacritics[row] .. codes.diacritics[col + 1]
  end
  return table.concat(line)
end

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
  width_px = math.max(1, tonumber(width_px) or 1)
  height_px = math.max(1, tonumber(height_px) or 1)
  local source_rows = track.source_rows or math.max(1, track.end_row - track.row + 1)
  local cell_w, cell_h = state.cell_size()
  local cols, rows

  if cell_w ~= nil and cell_h ~= nil then
    if track.source_display_kind ~= "block" and source_rows == 1 then
      local aspect = width_px / height_px
      cols = math.max(1, math.floor(cell_h * aspect / cell_w + 0.5))
      rows = 1
    else
      cols = math.max(1, math.floor(width_px / cell_w + 0.5))
      rows = math.max(1, math.floor(height_px / cell_h + 0.5))
    end
  elseif track.source_display_kind ~= "block" and source_rows == 1 then
    cols = math.max(1, math.floor((width_px / height_px) * 2))
    rows = 1
  else
    cols = math.ceil((width_px / height_px) * 2) * source_rows
    rows = source_rows
  end

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

function M.preview_cell_dimensions(width_px, height_px)
  width_px = math.max(1, tonumber(width_px) or 1)
  height_px = math.max(1, tonumber(height_px) or 1)
  local cell_w, cell_h = state.cell_size()
  local cols, rows

  if cell_w ~= nil and cell_h ~= nil then
    cols = math.max(1, math.floor(width_px / cell_w + 0.5))
    rows = math.max(1, math.floor(height_px / cell_h + 0.5))
  else
    cols = math.max(1, math.floor((width_px / height_px) * 2 + 0.5))
    rows = 1
  end

  return clamp_cells(cols, rows)
end

local function active_window_for_bufnr(bufnr)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current) and vim.api.nvim_win_get_buf(current) == bufnr then
    return current
  end

  local wins = vim.fn.win_findbuf(bufnr)
  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end
  return nil
end

local function preview_left_pad_cols(bufnr, row, col)
  local winid = active_window_for_bufnr(bufnr)
  if winid == nil then
    local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false) or { "" })[1] or ""
    return vim.fn.strdisplaywidth(line:sub(1, col))
  end

  local sp = vim.fn.screenpos(winid, row + 1, col + 1)
  local winpos = vim.api.nvim_win_get_position(winid)
  local wininfo = vim.fn.getwininfo(winid)[1] or {}
  local textoff = wininfo.textoff or 0
  local screen_col = math.max(1, (sp.col or 1) - winpos[2] - textoff)
  return screen_col - 1
end

local function range_screen_rect(bufnr, start_row, start_col, end_row, end_col)
  local winid = active_window_for_bufnr(bufnr)
  if winid == nil then
    return nil
  end

  local start_sp = vim.fn.screenpos(winid, start_row + 1, start_col + 1)
  local end_sp = vim.fn.screenpos(winid, end_row + 1, math.max(start_col + 1, end_col))
  if start_sp == nil or end_sp == nil or (start_sp.row or 0) <= 0 or (end_sp.row or 0) <= 0 then
    return nil
  end

  return {
    top = math.max(0, (start_sp.row or 1) - 1),
    bottom = math.max(0, (end_sp.row or 1) - 1),
  }
end

local function choose_preview_vertical(bufnr, preview, start_row, start_col, end_row, end_col, rows)
  local preferred = (preview and preview.vertical) or "above"
  local rect = range_screen_rect(bufnr, start_row, start_col, end_row, end_col)
  if rect == nil then
    return preferred
  end

  local editor_h = math.max(1, vim.o.lines - vim.o.cmdheight)
  local above_fits = rect.top - rows >= 0
  local below_fits = rect.bottom + rows + 1 <= editor_h
  if preferred == "above" and above_fits then
    return "above"
  end
  if preferred == "below" and below_fits then
    return "below"
  end
  if below_fits then
    return "below"
  end
  if above_fits then
    return "above"
  end
  return preferred
end

function M.clear_preview(preview, bufnr)
  if preview == nil then
    return
  end
  bufnr = bufnr or preview.bufnr
  if preview.extmark_id ~= nil and bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.preview_ns, preview.extmark_id)
  end
  preview.extmark_id = nil
end

function M.show_preview(bufnr, preview, track, asset)
  if
    preview == nil
    or track == nil
    or asset == nil
    or asset.image_id == nil
    or not vim.api.nvim_buf_is_valid(bufnr)
  then
    return false
  end

  local start_row, start_col, end_row, end_col = display_range(track)
  local cols, rows = clamp_cells(asset.cols, asset.rows)
  asset.cols = cols
  asset.rows = rows
  local vertical = choose_preview_vertical(bufnr, preview, start_row, start_col, end_row, end_col, rows)
  preview.vertical = vertical

  local pad = preview_left_pad_cols(bufnr, start_row, start_col)
  local pad_text = pad > 0 and string.rep(" ", pad) or ""
  local hl = state.image_hl_group(asset.image_id)
  local lines = {}
  for row = 1, rows do
    lines[#lines + 1] = { { pad_text, "" }, { placeholder_row(row, cols), hl } }
  end

  local anchor_row = vertical == "above" and start_row or end_row
  preview.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.preview_ns, anchor_row, 0, {
    id = preview.extmark_id,
    invalidate = true,
    priority = 230,
    virt_lines = lines,
    virt_lines_above = vertical == "above",
  })
  return true
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
