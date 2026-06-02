--- Neovim extmark management and kitty graphics protocol for math-conceal.image.
--- This is the Neovim display layer: extmark placement, image upload, concealing.
--- All display decisions come from semantics.display_kind.
--- block_padding_cols = 终端显示留白（Neovim display 层，与 Typst page width 正交）

local cursor_visibility = require("math-conceal.image.cursor-visibility")
local display = require("math-conceal.image.display")
local kitty_codes = require("math-conceal.image.kitty-codes")
local line_run = require("math-conceal.image.line-run")
local state = require("math-conceal.image.state")
local M = {}

local is_tmux = vim.env.TMUX ~= nil
local vim_stdout
local display_size_for_image

--- Pending terminal data buffer.  All kitty escape sequences are accumulated
--- here and flushed as a single atomic write via `M.flush_terminal_data()`.
--- This prevents interleaving with Neovim's own TUI output when many images
--- are cleared+re-created in the same event-loop tick (bind_overlay batches).
local pending_terminal_buf = {}

local function refresh_line_run_for_row(bufnr, row, opts)
  opts = opts or {}
  local refreshed = opts.line_run_refresh_rows
  if type(refreshed) == "table" then
    local key = tostring(bufnr) .. ":" .. tostring(row)
    if refreshed[key] then
      return false
    end
    refreshed[key] = true
  end
  return line_run.refresh_for_row(bufnr, row)
end

local function tmux_escape(message)
  return "\x1bPtmux;" .. message:gsub("\x1b", "\x1b\x1b") .. "\x1b\\"
end

local function send_terminal_data(data)
  pending_terminal_buf[#pending_terminal_buf + 1] = data
end

local function write_terminal_data(data)
  if vim.api.nvim_ui_send ~= nil then
    local ok = pcall(vim.api.nvim_ui_send, data)
    if ok then
      return
    end
  end

  vim_stdout = vim_stdout or assert(vim.loop.new_tty(1, false))
  vim_stdout:write(data)
end

--- Flush all pending kitty escape data to the terminal in one write.
function M.flush_terminal_data()
  if #pending_terminal_buf == 0 then
    return
  end
  local data = table.concat(pending_terminal_buf)
  pending_terminal_buf = {}
  write_terminal_data(data)
end

local function encode_kitty_escape(message)
  local payload = "\x1b_G" .. message .. "\x1b\\"
  if is_tmux then
    return tmux_escape(payload)
  end
  return payload
end

local function send_kitty_escape(message)
  send_terminal_data(encode_kitty_escape(message))
end

--- Upload an image to the terminal via kitty graphics protocol.
--- @param path    string  path to the PNG file
--- @param image_id integer
--- @param width   integer  in terminal cells
--- @param height  integer  in terminal cells
function M.create_image(path, image_id, width, height)
  local item = state.get_item_by_image_id(image_id)
  width, height = display_size_for_image(item, width, height)
  if item ~= nil then
    item.display_cols = width
    item.display_rows = height
  end

  path = vim.base64.encode(path)
  send_terminal_data(
    encode_kitty_escape("q=2,f=100,t=t,i=" .. image_id .. ";" .. path)
      .. encode_kitty_escape("q=2,a=p,U=1,i=" .. image_id .. ",c=" .. width .. ",r=" .. height)
  )
end

--- Delete an image from the terminal.
--- @param image_id integer
function M.clear_image(image_id)
  send_kitty_escape("q=2,a=d,d=i,i=" .. image_id)
  state.image_ids_in_use[image_id] = nil
end

--- Delete an image from the terminal without touching index tables.
--- Used by resources.lua which manages index tables centrally.
--- @param image_id integer
function M.clear_image_only(image_id)
  send_kitty_escape("q=2,a=d,d=i,i=" .. image_id)
end

--- Returns the column width of the window displaying bufnr (falls back to current window).
--- @param bufnr integer
--- @return integer
local function get_win_cols(bufnr)
  return state.visible_window_width(bufnr)
end

local function item_display_bufnr(item)
  if item == nil then
    return nil
  end
  if item.render_target == "float" then
    return item.target_bufnr or item.bufnr
  end
  return item.bufnr
end

display_size_for_image = function(item, natural_cols, natural_rows)
  local display_cols = math.max(1, tonumber(natural_cols) or 1)
  local display_rows = math.max(1, tonumber(natural_rows) or 1)
  local semantics = item and item.semantics or nil
  if item == nil or item.render_target == "float" or semantics == nil or semantics.display_kind ~= "block" then
    return display_cols, display_rows
  end

  local bufnr = item_display_bufnr(item)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return display_cols, display_rows
  end

  local win_cols = get_win_cols(bufnr)
  if win_cols <= 0 or display_cols <= win_cols then
    return display_cols, display_rows
  end

  local scaled_rows = math.max(1, math.ceil(display_rows * win_cols / display_cols))
  return win_cols, scaled_rows
end

--- Returns leading spaces needed to centre an image of natural_cols width.
--- @param natural_cols integer
--- @param bufnr        integer
--- @return integer
local function center_padding(natural_cols, bufnr)
  local win_width = get_win_cols(bufnr)
  if natural_cols >= win_width then
    return 0
  end
  return math.floor((win_width - natural_cols) / 2)
end

local conceal_extmark_with_image

local function get_win_text_cols(bufnr)
  return state.visible_window_text_width(bufnr)
end

line_run.configure({
  display_size_for_image = display_size_for_image,
  item_display_bufnr = item_display_bufnr,
})

local function clear_inline_line_mark(bufnr, row)
  return line_run.clear_inline_line_mark(bufnr, row)
end

local function row_in_range(row, start_row, end_row)
  if type(row) ~= "number" then
    return false
  end
  if type(start_row) == "number" and row < start_row then
    return false
  end
  if type(end_row) == "number" and row > end_row then
    return false
  end
  return true
end

local function extmark_row(bufnr, ns_id, extmark_id)
  if type(extmark_id) ~= "number" then
    return nil
  end
  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, {})
  if not ok or mark == nil or #mark == 0 then
    return nil
  end
  return mark[1]
end

--- Clear compact inline line carriers in a buffer range.
--- Row-keyed compact carriers can drift after line insertions/deletions because
--- Neovim moves their extmarks, but the Lua table key still names the old row.
--- A nil end_row means "from start_row to the end of the buffer".
--- @param bufnr integer
--- @param start_row integer|nil
--- @param end_row integer|nil
--- @return integer
function M.clear_inline_line_marks(bufnr, start_row, end_row)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  local bs = state.get_buf_state(bufnr)
  local cleared = line_run.clear_inline_line_marks(bufnr, start_row, end_row)

  local attachments = bs.inline_line_attachment_marks or {}
  local attachment_extmark_ids = {}
  for extmark_id, meta in pairs(attachments) do
    if
      row_in_range(meta.row, start_row, end_row)
      or row_in_range(extmark_row(bufnr, state.ns_id2, meta.attach_id), start_row, end_row)
    then
      attachment_extmark_ids[#attachment_extmark_ids + 1] = extmark_id
    end
  end
  for _, extmark_id in ipairs(attachment_extmark_ids) do
    local meta = attachments[extmark_id]
    if meta and meta.attach_id ~= nil then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, meta.attach_id)
    end
    attachments[extmark_id] = nil
  end
  bs.inline_line_attachment_marks = attachments

  return cleared
end

local function image_hl_group(image_id)
  local hl_group = "math-conceal.image-image-id-" .. tostring(image_id)
  vim.api.nvim_set_hl(0, hl_group, { fg = string.format("#%06X", image_id), nocombine = true })
  return hl_group
end

local function item_for_extmark_id(bufnr, extmark_id)
  if type(extmark_id) ~= "number" then
    return nil
  end
  for _, item in pairs(state.item_by_image_id) do
    if
      item ~= nil
      and item_display_bufnr(item) == bufnr
      and (item.extmark_id == extmark_id or state.image_id_to_extmark[item.image_id] == extmark_id)
    then
      return item
    end
  end
end

local function image_placeholder_text(display_cols, image_row)
  local line = ""
  for col = 0, display_cols - 1 do
    line = line .. kitty_codes.placeholder .. kitty_codes.diacritics[image_row] .. kitty_codes.diacritics[col + 1]
  end
  return line
end

local function clear_inline_line_attachment(bufnr, extmark_id)
  local bs = state.get_buf_state(bufnr)
  local attachments = bs.inline_line_attachment_marks or {}
  local meta = attachments[extmark_id]
  if meta == nil then
    return nil
  end
  if meta.attach_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, meta.attach_id)
  end
  attachments[extmark_id] = nil
  bs.inline_line_attachment_marks = attachments
  return meta
end

local function set_inline_source_conceal_only(bufnr, extmark_id)
  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, state.ns_id, extmark_id, { details = true })
  if not ok or mark == nil or #mark == 0 then
    return nil
  end

  local row, col, opts = mark[1], mark[2], mark[3] or {}
  vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, {
    id = extmark_id,
    virt_text = { { "" } },
    virt_text_pos = opts.virt_text_pos or "inline",
    conceal = "",
    invalidate = opts.invalidate,
    end_col = opts.end_col,
    end_row = opts.end_row,
  })
  return {
    row = row,
    end_col = opts.end_col,
  }
end

local function attach_inline_image_after_source(bufnr, item, extmark_id, natural_cols, natural_rows)
  if item == nil or type(item.range) ~= "table" or item.range[1] ~= item.range[3] then
    return false
  end
  local bs = state.get_buf_state(bufnr)
  if bs.currently_hidden_extmark_ids and bs.currently_hidden_extmark_ids[extmark_id] then
    return false
  end
  if cursor_visibility.should_preserve_source_at_cursor(bufnr, item) then
    return false
  end

  local display_cols, display_rows = display_size_for_image(item, natural_cols, natural_rows)
  if display_rows ~= 1 then
    return false
  end
  item.display_cols = display_cols
  item.display_rows = display_rows

  local source = set_inline_source_conceal_only(bufnr, extmark_id)
  if source == nil then
    return false
  end

  clear_inline_line_attachment(bufnr, extmark_id)
  local attach_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id2, item.range[1], item.range[4], {
    virt_text = {
      {
        image_placeholder_text(display_cols, 1),
        image_hl_group(item.image_id),
      },
    },
    virt_text_pos = "inline",
    invalidate = true,
  })

  bs.inline_line_attachment_marks = bs.inline_line_attachment_marks or {}
  bs.inline_line_attachment_marks[extmark_id] = {
    row = item.range[1],
    image_id = item.image_id,
    attach_id = attach_id,
  }
  return true
end

local function restore_row_attached_extmark(bufnr, extmark_id, opts)
  opts = opts or {}
  local meta = clear_inline_line_attachment(bufnr, extmark_id)
  if meta == nil then
    return false
  end

  local bs = state.get_buf_state(bufnr)
  if bs.currently_hidden_extmark_ids and bs.currently_hidden_extmark_ids[extmark_id] then
    return false
  end

  local item = item_for_extmark_id(bufnr, extmark_id)
  if item == nil or item.natural_cols == nil or item.natural_rows == nil then
    return false
  end

  local range = item.range or item.display_range
  local source_rows = item.source_rows
  if source_rows == nil and type(range) == "table" then
    source_rows = (range[3] or range[1]) - range[1] + 1
  end
  conceal_extmark_with_image(
    bufnr,
    extmark_id,
    item.image_id,
    item.natural_cols,
    item.natural_rows,
    source_rows or 1,
    item,
    opts
  )
  return true
end

local place_image_extmark

--- Clamp a range to the current buffer contents so extmark updates survive edits.
--- @param bufnr integer
--- @param range Range4
--- @return Range4|nil
local function normalize_range(bufnr, range)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return nil
  end

  local start_row = math.max(0, math.min(range[1], line_count - 1))
  local end_row = math.max(start_row, math.min(range[3], line_count - 1))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)

  local start_len = #(lines[1] or "")
  local end_len = #(lines[#lines] or "")
  local start_col = math.max(0, math.min(range[2], start_len))
  local end_col = math.max(0, math.min(range[4], end_len))

  if start_row == end_row and end_col < start_col then
    end_col = start_col
  end

  return { start_row, start_col, end_row, end_col }
end

--- Normalize virt text payload into one extmark line: { {text, hl?}, ... }.
--- Accepts chunk, line, or single-item virt_lines forms.
--- @param value any
--- @return table
local function normalize_virt_text_line(value)
  if type(value) ~= "table" then
    return { { tostring(value or ""), "" } }
  end

  if type(value[1]) == "string" then
    return { value }
  end

  if type(value[1]) == "table" and type(value[1][1]) == "string" then
    return value
  end

  if type(value[1]) == "table" and type(value[1][1]) == "table" then
    return normalize_virt_text_line(value[1])
  end

  return { { "", "" } }
end

local function normalize_virt_text_lines(value)
  if type(value) ~= "table" then
    return { normalize_virt_text_line(value) }
  end

  if type(value[1]) == "table" and type(value[1][1]) == "table" then
    local lines = {}
    for i = 1, #value do
      lines[i] = normalize_virt_text_line(value[i])
    end
    return lines
  end

  return { normalize_virt_text_line(value) }
end

--- Low-level extmark placement. Use place_render_extmark for external callers.
--- @param bufnr      integer
--- @param image_id  integer
--- @param range     Range4
--- @param extmark_id integer|nil
--- @param concealing boolean|nil
--- @param is_block  boolean|nil
--- @return integer  new extmark_id
place_image_extmark = function(bufnr, image_id, range, extmark_id, concealing, is_block)
  local normalized = normalize_range(bufnr, range)
  if normalized == nil then
    return extmark_id
  end

  local start_row, start_col, end_row, end_col = normalized[1], normalized[2], normalized[3], normalized[4]
  local height = end_row - start_row + 1
  local new_extmark_id
  local bs = state.get_buf_state(bufnr)

  if height == 1 then
    if concealing == false then
      local opts = {
        id = extmark_id,
        invalidate = true,
        end_col = end_col,
        end_row = end_row,
      }
      if is_block then
        opts.virt_text = { { "" } }
        opts.virt_text_pos = "overlay"
      else
        opts.virt_text = { { "" } }
        opts.virt_text_pos = "inline"
      end
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, opts)
      if is_block then
        bs.multiline_marks[new_extmark_id] = { is_block_carrier = true, carrier_id = nil, tail_ids = {} }
      end
    elseif is_block then
      -- Single-line block formulas also use the block-carrier model so they can
      -- expand to multiple display rows and fully conceal the source line.
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, {
        id = extmark_id,
        virt_text = { { "" } },
        virt_text_pos = "overlay",
        invalidate = true,
        end_col = end_col,
        end_row = end_row,
      })
      bs.multiline_marks[new_extmark_id] = { is_block_carrier = true, carrier_id = nil, tail_ids = {} }
    else
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, {
        id = extmark_id,
        virt_text = { { "" } },
        virt_text_pos = "inline",
        conceal = "",
        invalidate = true,
        end_col = end_col,
        end_row = end_row,
      })
    end
  else
    if concealing == false then
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, {
        id = extmark_id,
        invalidate = true,
        virt_text = { { "" } },
        -- used for determining the virt_text_pos of child ns_id2 extmarks
        virt_text_pos = is_block and "overlay" or "right_align",
        end_col = end_col,
        end_row = end_row,
      })
      if is_block then
        bs.multiline_marks[new_extmark_id] = { is_block_carrier = true, carrier_id = nil, tail_ids = {} }
      else
        bs.multiline_marks[new_extmark_id] = {}
      end
    elseif is_block then
      -- Block multi-line: top-carrier atomic model.
      -- One ns_id2 carrier at start_row carries all image rows via virt_text+virt_lines.
      -- Tail ns_id2 extmarks conceal source rows start_row+1..end_row.
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, {
        id = extmark_id,
        invalidate = true,
        virt_text = { { "" } },
        virt_text_pos = "overlay",
        end_col = end_col,
        end_row = end_row,
      })
      bs.multiline_marks[new_extmark_id] = { is_block_carrier = true, carrier_id = nil, tail_ids = {} }
    else
      new_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_row, start_col, {
        id = extmark_id,
        invalidate = true,
        virt_text = { { "" } },
        virt_text_pos = "overlay",
        end_col = end_col,
        end_row = end_row,
      })
      bs.multiline_marks[new_extmark_id] = {}
    end
  end

  state.image_id_to_extmark[image_id] = new_extmark_id
  return new_extmark_id
end

--- Public entry: place an extmark driven by render semantics.
--- Display decision comes only from semantics.display_kind.
--- @param bufnr      integer
--- @param image_id   integer
--- @param range      Range4
--- @param extmark_id integer|nil
--- @param concealing boolean|nil
--- @param semantics  table  RenderSemantics
--- @return integer
function M.place_render_extmark(bufnr, image_id, range, extmark_id, concealing, semantics)
  local is_block = (semantics.display_kind == "block")
  return place_image_extmark(bufnr, image_id, range, extmark_id, concealing, is_block)
end

--- Rebuild an existing extmark in-place for a new range.
--- Keeps the old rendered image visible until swap time.
--- @param bufnr      integer
--- @param image_id   integer
--- @param extmark_id integer
--- @param range      Range4
--- @param semantics  table  RenderSemantics
--- @param concealing boolean|nil
function M.swap_extmark_to_range(bufnr, image_id, extmark_id, range, semantics, concealing)
  state.prepare_extmark_reuse(bufnr, extmark_id)
  local new_id = place_image_extmark(bufnr, image_id, range, extmark_id, concealing, semantics.display_kind == "block")
  state.image_id_to_extmark[image_id] = new_id
end

--- Remove rendered placeholder text/conceal from an extmark so the source stays editable.
--- @param bufnr integer
--- @param extmark_id integer
--- @param opts table|nil
--- @return boolean|nil
function M.unconceal_extmark(bufnr, extmark_id, opts)
  opts = opts or {}
  local defer_line_run_reconcile = opts.defer_line_run_reconcile == true
  local bs = state.get_buf_state(bufnr)
  clear_inline_line_attachment(bufnr, extmark_id)
  local ok_mark, current_mark =
    pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, state.ns_id, extmark_id, { details = true })
  local source_start_row = nil
  local source_end_row = nil
  if ok_mark and current_mark ~= nil and #current_mark > 0 then
    source_start_row = current_mark[1]
    source_end_row = (current_mark[3] and current_mark[3].end_row) or source_start_row
    clear_inline_line_mark(bufnr, source_start_row)
  end

  local mm = bs.multiline_marks[extmark_id]
  if mm ~= nil then
    if mm.is_block_carrier then
      local start_row = source_start_row
      local end_row = source_end_row or start_row
      if mm.line_run_id ~= nil then
        line_run.clear(bufnr, mm.line_run_id)
        mm.line_run_display_lines = nil
        if not defer_line_run_reconcile then
          line_run.refresh_around_range(bufnr, start_row, end_row, {
            anchor_rows = line_run.row_set(start_row, end_row),
            suppressed_extmark_ids = {
              [extmark_id] = true,
            },
          })
        end
        return true
      end
      if mm.carrier_id then
        vim.api.nvim_buf_del_extmark(bufnr, state.ns_id2, mm.carrier_id)
        mm.carrier_id = nil
      end
      for _, sid in ipairs(mm.tail_ids or {}) do
        vim.api.nvim_buf_del_extmark(bufnr, state.ns_id2, sid)
      end
      mm.tail_ids = {}
      return true
    end

    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.ns_id, extmark_id, { details = true })
    if #mark > 0 and mark[3] and mark[3].virt_text_pos == "right_align" then
      return nil
    end
    if mm.line_run_id ~= nil then
      line_run.clear(bufnr, mm.line_run_id)
      return mm.conceals_source ~= false and true or nil
    end
    for _, sub_id in ipairs(mm) do
      if type(sub_id) == "number" then
        vim.api.nvim_buf_del_extmark(bufnr, state.ns_id2, sub_id)
      end
    end
    return true
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.ns_id, extmark_id, { details = true })
  if #mark == 0 then
    return nil
  end
  local row, col, mark_opts = mark[1], mark[2], mark[3]
  vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, {
    id = extmark_id,
    virt_text = { { "" } },
    end_row = mark_opts.end_row,
    end_col = mark_opts.end_col,
    conceal = nil,
    virt_text_pos = mark_opts.virt_text_pos,
    invalidate = mark_opts.invalidate,
  })
  if not defer_line_run_reconcile then
    line_run.refresh_around_range(bufnr, row, mark_opts.end_row or row, {
      anchor_rows = line_run.row_set(row, mark_opts.end_row or row),
      suppressed_extmark_ids = {
        [extmark_id] = true,
      },
      suppressed_rows = line_run.row_set(row, mark_opts.end_row or row),
    })
  end
  return true
end

--- Reconcile all line-run carriers after a cursor visibility transition.
--- Atomic show/hide operations only mutate their own source extmark/image
--- payload; this scheduler owns cross-extmark grouping, splitting and anchor
--- selection for the final hidden set.
--- @param bufnr integer
--- @param lo integer
--- @param hi integer|nil
function M.reconcile_cursor_line_runs(bufnr, lo, hi)
  return line_run.reconcile_cursor_line_runs(bufnr, lo, hi, {
    restore_row_attached_extmark = restore_row_attached_extmark,
    attach_inline_image_after_source = attach_inline_image_after_source,
  })
end

--- Back-compat alias for older callers.
--- @param bufnr integer
--- @param lo integer
--- @param hi integer|nil
function M.sync_inline_line_carriers(bufnr, lo, hi)
  return M.reconcile_cursor_line_runs(bufnr, lo, hi)
end

--- Update the virt_text/virt_lines on an existing extmark.
--- @param bufnr           integer
--- @param extmark_id      integer
--- @param virt_text_data  table
--- @param skip_hide_check boolean|nil
--- @param opts table|nil
function M.update_extmark_text(bufnr, extmark_id, virt_text_data, skip_hide_check, opts)
  if type(extmark_id) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local update_opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  if (skip_hide_check ~= true) and bs.currently_hidden_extmark_ids[extmark_id] ~= nil then
    return
  end
  local ok, m = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, state.ns_id, extmark_id, { details = true })
  if not ok then
    return
  end
  if #m == 0 then
    return
  end
  local row, col, mark_opts = m[1], m[2], m[3]
  local single_line = normalize_virt_text_line(virt_text_data)

  local mm = bs.multiline_marks[extmark_id]
  if mm and mm.is_block_carrier then
    -- Top-carrier atomic model: one ns_id2 carrier owns the visible display.
    local start_row = row
    if mm.line_run_id ~= nil then
      line_run.clear(bufnr, mm.line_run_id)
    elseif mm.carrier_id then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, mm.carrier_id)
      mm.carrier_id = nil
      for _, id in ipairs(mm.tail_ids or {}) do
        pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, id)
      end
    end
    mm.tail_ids = {}

    local display_lines = normalize_virt_text_lines(virt_text_data)
    mm.line_run_display_lines = display_lines
    if update_opts.defer_line_run_reconcile ~= true then
      refresh_line_run_for_row(bufnr, start_row, update_opts)
    end
    return
  else
    local height = mark_opts.end_row - row + 1
    if height ~= 1 then
      if mm then
        if mm.line_run_id ~= nil then
          line_run.clear(bufnr, mm.line_run_id)
        else
          for _, id in pairs(mm) do
            if type(id) == "number" then
              pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, id)
            end
          end
        end
      end

      local run_id = (bs.next_line_run_id or 0) + 1
      bs.next_line_run_id = run_id
      bs.line_run_marks = bs.line_run_marks or {}
      bs.line_run_by_row = bs.line_run_by_row or {}
      bs.line_run_by_extmark = bs.line_run_by_extmark or {}

      local lines = vim.api.nvim_buf_get_lines(bufnr, row, mark_opts.end_row + 1, false)
      local sub_ids = {}
      for i = 1, height do
        local source_row = row + i - 1
        local conceal = nil
        if mark_opts.virt_text_pos ~= "right_align" then
          conceal = ""
        end
        local virt_text_line = virt_text_data[i]
        if
          type(virt_text_line) == "string"
          or (type(virt_text_line) == "table" and type(virt_text_line[1]) == "string")
        then
          virt_text_line = { virt_text_line }
        end
        local new_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id2, row + i - 1, 0, {
          virt_text = virt_text_line,
          conceal = conceal,
          virt_text_pos = mark_opts.virt_text_pos,
          end_col = #(lines[i] or ""),
          end_row = row + i - 1,
        })
        sub_ids[#sub_ids + 1] = new_id
        bs.line_run_by_row[source_row] = run_id
      end

      bs.line_run_marks[run_id] = {
        mode = "row_overlay",
        sub_ids = sub_ids,
        extmark_ids = {
          [extmark_id] = true,
        },
      }
      bs.line_run_by_extmark[extmark_id] = run_id
      bs.multiline_marks[extmark_id] = {
        is_multiline_overlay = true,
        line_run_id = run_id,
        sub_ids = sub_ids,
        conceals_source = mark_opts.virt_text_pos ~= "right_align",
      }
    elseif
      mark_opts.virt_text_pos == "inline" or (mark_opts.virt_text_pos == "overlay" and mark_opts.conceal == "")
    then
      vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, {
        id = extmark_id,
        virt_text = single_line,
        virt_text_pos = mark_opts.virt_text_pos,
        invalidate = mark_opts.invalidate,
        end_col = mark_opts.end_col,
        end_row = mark_opts.end_row,
        --- @diagnostic disable-next-line nvim type is wrong
        conceal = "",
      })
    else
      vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, {
        id = extmark_id,
        virt_lines = { single_line },
        virt_text_pos = mark_opts.virt_text_pos,
        invalidate = mark_opts.invalidate,
        end_col = mark_opts.end_col,
        end_row = mark_opts.end_row,
        --- @diagnostic disable-next-line nvim type is wrong
        conceal = mark_opts.conceal,
      })
    end
  end
end

--- Shared placeholder writer used by both main-buffer items and preview-float clones.
--- @param bufnr integer
--- @param extmark_id integer
--- @param render_image_id integer
--- @param natural_cols integer
--- @param natural_rows integer
--- @param source_rows integer
--- @param item table|nil
--- @param opts table|nil
conceal_extmark_with_image = function(
  bufnr,
  extmark_id,
  render_image_id,
  natural_cols,
  natural_rows,
  source_rows,
  item,
  opts
)
  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  if type(extmark_id) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local multiline_extmark_ids = bs.multiline_marks[extmark_id]
  local display_cols, display_rows = display_size_for_image(item, natural_cols, natural_rows)
  if item ~= nil then
    item.display_cols = display_cols
    item.display_rows = display_rows
  end

  local hl_group = "math-conceal.image-image-id-" .. tostring(render_image_id)
  vim.api.nvim_set_hl(0, hl_group, { fg = string.format("#%06X", render_image_id), nocombine = true })

  local config = require("math-conceal.image").config
  local pad = 0
  if item and item.render_target == "float" then
    pad = 0
  elseif item and item.semantics then
    if item.semantics.constraint_kind == "flow" then
      -- Multiline code: left padding = terminal display padding
      -- block_padding_cols = 终端显示留白（Neovim display 层）
      pad = config.block_padding_cols or 0
    elseif item.semantics.display_kind == "block" then
      -- Math display (single- or multi-line): centre in the buffer's own window
      pad = center_padding(display_cols, bufnr)
    end
  end

  local pad_str = pad > 0 and string.rep(" ", pad) or nil

  local function make_row_list(i)
    local line = ""
    for j = 0, display_cols - 1 do
      line = line .. kitty_codes.placeholder .. kitty_codes.diacritics[i] .. kitty_codes.diacritics[j + 1]
    end
    if pad_str then
      return { { pad_str, "" }, { line, hl_group } }
    end
    return { { line, hl_group } }
  end

  local too_tall_msg = "This image attempted to render taller than "
    .. #kitty_codes.diacritics
    .. " lines. If you legitimately see this in a real document, open an issue."

  local function build_image_lines()
    local lines = {}
    for i = 1, display_rows do
      if i >= #kitty_codes.diacritics then
        lines[#lines + 1] = { { too_tall_msg, hl_group } }
      else
        lines[#lines + 1] = make_row_list(i)
      end
    end
    return lines
  end

  local function build_block_display_lines()
    local lines = {}
    local image_lines = build_image_lines()
    local source_range = item and item.range or nil
    local sem = item and item.semantics or nil

    if
      sem
      and sem.render_whole_line == true
      and type(source_range) == "table"
      and source_range[1] == source_range[3]
    then
      local composed = display.line_block_virt_lines(
        bufnr,
        source_range[1],
        {
          source = "math-conceal.image-block-image",
          start_col = source_range[2],
          end_col = source_range[4],
          priority = 10000,
          lines = image_lines,
        },
        get_win_text_cols(bufnr),
        {
          exclude_namespaces = {
            [state.ns_id] = true,
            [state.ns_id2] = true,
          },
        }
      )

      if composed ~= nil then
        return composed
      end
    end

    local prefix = item and item.display_prefix or nil
    local suffix = item and item.display_suffix or nil

    if type(prefix) == "string" and prefix ~= "" then
      lines[#lines + 1] = { { prefix, "" } }
    end
    for _, image_line in ipairs(image_lines) do
      lines[#lines + 1] = image_line
    end
    if type(suffix) == "string" and suffix ~= "" then
      lines[#lines + 1] = { { suffix, "" } }
    end

    return lines
  end

  if multiline_extmark_ids == nil then
    M.update_extmark_text(bufnr, extmark_id, make_row_list(1), nil, opts)
  elseif multiline_extmark_ids.is_block_carrier then
    M.update_extmark_text(bufnr, extmark_id, build_block_display_lines(), nil, opts)
  else
    -- Non-block multiline: existing centering logic
    local lines = {}
    if display_rows < source_rows then
      local above_blank = math.floor((source_rows - display_rows) / 2)
      for i = 1, source_rows do
        local image_row = i - above_blank
        if image_row < 1 or image_row > display_rows then
          lines[i] = { { "", hl_group } }
        elseif image_row >= #kitty_codes.diacritics then
          lines[i] = { { too_tall_msg, hl_group } }
        else
          lines[i] = make_row_list(image_row)
        end
      end
    else
      for i = 1, source_rows do
        if i >= #kitty_codes.diacritics then
          lines[i] = { { too_tall_msg, hl_group } }
        else
          lines[i] = make_row_list(i)
        end
      end
    end
    M.update_extmark_text(bufnr, extmark_id, lines, nil, opts)
  end

  if
    item ~= nil
    and item.semantics ~= nil
    and item.semantics.display_kind == "inline"
    and item.range ~= nil
    and item.range[1] == item.range[3]
    and opts.defer_line_run_reconcile ~= true
  then
    refresh_line_run_for_row(bufnr, item.range[1], opts)
  end
end

--- Add concealing unicode characters for a rendered image.
--- Padding decision comes from the item's semantics (looked up from state).
---   flow + block  → block_padding_cols left padding (terminal display layer)
---   intrinsic + block → centred
---   inline        → no padding
--- @param bufnr        integer
--- @param image_id     integer
--- @param natural_cols integer
--- @param natural_rows integer
--- @param source_rows  integer
--- @param opts table|nil
function M.conceal_for_image_id(bufnr, image_id, natural_cols, natural_rows, source_rows, opts)
  opts = opts or {}
  local extmark_id = state.image_id_to_extmark[image_id]
  local bs = state.get_buf_state(bufnr)
  local item = state.get_item_by_image_id(image_id)
  if extmark_id ~= nil and bs.inline_line_attachment_marks and bs.inline_line_attachment_marks[extmark_id] then
    attach_inline_image_after_source(bufnr, item, extmark_id, natural_cols, natural_rows)
    return
  end
  if extmark_id ~= nil and cursor_visibility.should_preserve_source_at_cursor(bufnr, item) then
    if M.unconceal_extmark(bufnr, extmark_id, opts) ~= nil then
      bs.currently_hidden_extmark_ids[extmark_id] = true
    end
    return
  end
  if extmark_id ~= nil and bs.currently_hidden_extmark_ids[extmark_id] then
    return
  end
  conceal_extmark_with_image(bufnr, extmark_id, image_id, natural_cols, natural_rows, source_rows, item, opts)
  require("math-conceal.image.presentation").keep_cursor_out_of_protected_range(bufnr)
end

--- Render an existing kitty image into an arbitrary extmark.
--- Used by preview float so it can reuse the exact full-render image payload.
--- @param bufnr integer
--- @param extmark_id integer
--- @param render_image_id integer
--- @param natural_cols integer
--- @param natural_rows integer
--- @param source_rows integer
--- @param item table|nil
function M.conceal_existing_image(bufnr, extmark_id, render_image_id, natural_cols, natural_rows, source_rows, item)
  conceal_extmark_with_image(bufnr, extmark_id, render_image_id, natural_cols, natural_rows, source_rows, item)
end

--- Render an existing kitty image into virtual lines above or below a buffer row.
--- Unlike conceal_existing_image, this never conceals source text.
--- @param bufnr integer
--- @param extmark_id integer|nil
--- @param anchor_row integer
--- @param render_image_id integer
--- @param natural_cols integer
--- @param natural_rows integer
--- @param opts table|nil
--- @return integer
function M.show_virtual_image(bufnr, extmark_id, anchor_row, render_image_id, natural_cols, natural_rows, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return extmark_id
  end

  opts = opts or {}
  local left_pad_cols = math.max(0, opts.left_pad_cols or 0)
  local pad_str = left_pad_cols > 0 and string.rep(" ", left_pad_cols) or nil
  local hl_group = "math-conceal.image-image-id-" .. tostring(render_image_id)
  vim.api.nvim_set_hl(0, hl_group, { fg = string.format("#%06X", render_image_id), nocombine = true })

  local lines = {}
  local too_tall_msg = "This image attempted to render taller than "
    .. #kitty_codes.diacritics
    .. " lines. If you legitimately see this in a real document, open an issue."

  for i = 1, natural_rows do
    local line = ""
    if i >= #kitty_codes.diacritics then
      line = too_tall_msg
    else
      for j = 0, natural_cols - 1 do
        line = line .. kitty_codes.placeholder .. kitty_codes.diacritics[i] .. kitty_codes.diacritics[j + 1]
      end
    end
    if pad_str then
      lines[#lines + 1] = { { pad_str, "" }, { line, hl_group } }
    else
      lines[#lines + 1] = { { line, hl_group } }
    end
  end

  return vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, anchor_row, 0, {
    id = extmark_id,
    invalidate = true,
    virt_lines = lines,
    virt_lines_above = opts.above == true,
  })
end

return M
