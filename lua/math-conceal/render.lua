---realization of fine grained math conceal rendering using persistent extmarks with incremental updates
---@class MathConcealRender
local M = {}

local utils = require("math-conceal.utils")
local queries = {
  latex = require("math-conceal.symbols.latex"),
  typst = require("math-conceal.symbols.typst"),
}

---@class BufferCacheItem
---@field parser vim.treesitter.LanguageTree
---@field query table Tree-sitter query object
---@field lang string Language type

---@type table<number, BufferCacheItem>
local buffer_cache = {}
local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

---Store currently revealed (hidden) extmarks to restore them later
---Structure: { [buf_id] = { [extmark_id] = { r1, c1, opts } } }
local hidden_extmarks = {}

---Safe wrapper for get_parsed_query
local query_obj_cache = {}
local function get_parsed_query(lang, query_string)
  local cache_key = lang .. ":" .. query_string
  if query_obj_cache[cache_key] then
    return query_obj_cache[cache_key]
  end

  local success, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if success and query then
    query_obj_cache[cache_key] = query
    return query
  else
    return nil
  end
end

---Check if cursor is "touching" the range [r1, c1) to [r2, c2)
---@param strict boolean If true, cursor must be strictly inside (col < c2). If false, cursor can be at end (col <= c2).
local function is_cursor_touching(cursor_row, cursor_col, r1, c1, r2, c2, strict)
  if strict then
    -- Normal mode: Strict check
    return (cursor_row > r1 and cursor_row < r2)
      or (cursor_row == r1 and cursor_row == r2 and cursor_col >= c1 and cursor_col < c2)
      or (cursor_row == r1 and cursor_row < r2 and cursor_col >= c1)
      or (cursor_row > r1 and cursor_row == r2 and cursor_col < c2)
  else
    -- Insert mode: Loose check
    return (cursor_row > r1 and cursor_row < r2)
      or (cursor_row == r1 and cursor_row == r2 and cursor_col >= c1 and cursor_col <= c2)
      or (cursor_row == r1 and cursor_row < r2 and cursor_col >= c1)
      or (cursor_row > r1 and cursor_row == r2 and cursor_col <= c2)
  end
end

---Render conceal extmarks for a specific range of rows
---@param buf number
---@param start_row number 0-indexed, inclusive
---@param end_row number 0-indexed, exclusive
local function render_range(buf, start_row, end_row)
  if not buffer_cache[buf] then
    return
  end
  local cache = buffer_cache[buf]

  vim.api.nvim_buf_clear_namespace(buf, ns_id, start_row, end_row)

  local trees = cache.parser:trees()
  local tree = trees and trees[1]
  if not tree then
    return
  end
  local root = tree:root()

  -- Anti-flicker preparation
  local cursor = vim.api.nvim_win_get_cursor(0)
  local curr_row, curr_col = cursor[1] - 1, cursor[2]
  local mode = vim.api.nvim_get_mode().mode
  local is_insert = mode:match("^[iR]")
  local is_active_buf = (vim.api.nvim_get_current_buf() == buf)

  for id, node, metadata in cache.query:iter_captures(root, buf, start_row, end_row) do
    local r1, c1, r2, c2 = node:range()

    if r1 >= start_row and r1 < end_row then
      local capture_data = metadata[id]
      local conceal_char = capture_data and capture_data.conceal or metadata.conceal

      if conceal_char then
        local priority = (capture_data and capture_data.priority) or metadata.priority or 100
        local hl_group = (capture_data and capture_data.highlight) or metadata.highlight or "Conceal"

        local opts = {
          conceal = conceal_char,
          hl_group = hl_group,
          priority = tonumber(priority),
          end_row = r2,
          end_col = c2,
          ephemeral = false,
        }

        -- ANTI-FLICKER: Only apply in INSERT mode to prevent typing flicker.
        local should_reveal_now = is_active_buf
          and is_insert
          and is_cursor_touching(curr_row, curr_col, r1, c1, r2, c2, false)

        if should_reveal_now then
          local new_id = vim.api.nvim_buf_set_extmark(buf, ns_id, r1, c1, opts)
          if not hidden_extmarks[buf] then
            hidden_extmarks[buf] = {}
          end
          hidden_extmarks[buf][new_id] = {
            r1 = r1,
            c1 = c1,
            r2 = r2,
            c2 = c2,
            opts = opts,
          }
          vim.api.nvim_buf_del_extmark(buf, ns_id, new_id)
        else
          vim.api.nvim_buf_set_extmark(buf, ns_id, r1, c1, opts)
        end
      end
    end
  end
end

---Refresh extmarks visibility based on cursor position
local function cursor_refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local mode = vim.api.nvim_get_mode().mode
  local is_insert = mode:match("^[iR]")

  if not hidden_extmarks[buf] then
    hidden_extmarks[buf] = {}
  end

  -- Determine strictness based on mode
  -- Insert: Loose (allow end touching) -> Better typing experience
  -- Normal: Strict (must be inside) -> Standard behavior
  local strict_check = not is_insert

  -- 1. Restore Logic
  local to_restore = {}
  for id, saved in pairs(hidden_extmarks[buf]) do
    if saved and saved.r1 then
      -- If cursor is NOT touching the area (based on current mode's strictness), restore it.
      if not is_cursor_touching(row, col, saved.r1, saved.c1, saved.r2, saved.c2, strict_check) then
        to_restore[id] = true
      end
    else
      to_restore[id] = true
    end
  end

  for id, _ in pairs(to_restore) do
    local saved = hidden_extmarks[buf][id]
    if saved and saved.opts then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, saved.r1, saved.c1, saved.opts)
    end
    hidden_extmarks[buf][id] = nil
  end

  -- 2. Reveal Logic
  -- Scan for marks that we are "touching"
  -- Using col+1 to ensure we catch adjacent marks in loose check
  local search_end_col = col + 1
  if not is_insert then
    search_end_col = col
  end -- Normal mode optimization

  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, { row, 0 }, { row, search_end_col }, { details = true })

  for _, m in ipairs(marks) do
    local id, r1, c1, details = m[1], m[2], m[3], m[4]
    local r2 = details.end_row or r1
    local c2 = details.end_col or c1

    if is_cursor_touching(row, col, r1, c1, r2, c2, strict_check) and not hidden_extmarks[buf][id] then
      hidden_extmarks[buf][id] = {
        r1 = r1,
        c1 = c1,
        r2 = r2,
        c2 = c2,
        opts = {
          conceal = details.conceal,
          hl_group = details.hl_group,
          priority = details.priority,
          end_row = r2,
          end_col = c2,
          ephemeral = false,
        },
      }
      vim.api.nvim_buf_del_extmark(buf, ns_id, id)
    end
  end
end

---Attach to buffer: Initial render + Event listeners
local function attach_to_buffer(buf, lang, query_string)
  if buffer_cache[buf] then
    return
  end

  local query = get_parsed_query(lang, query_string)
  local parser = vim.treesitter.get_parser(buf, lang)
  if not query or not parser then
    return
  end

  buffer_cache[buf] = {
    parser = parser,
    query = query,
    lang = lang,
  }

  -- 1. Initial Render
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      local line_count = vim.api.nvim_buf_line_count(buf)
      render_range(buf, 0, line_count)
    end
  end)

  -- 2. Incremental Updates using on_changedtree
  parser:register_cbs({
    on_changedtree = function(changes, tree)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        local root = tree:root()
        local line_count = vim.api.nvim_buf_line_count(buf)

        for _, change in ipairs(changes) do
          local start_row = change[1]
          local start_col = change[2]
          local node = root:named_descendant_for_range(start_row, start_col, start_row, start_col)

          local end_row
          if node then
            local _, _, r2, _ = node:range()
            end_row = r2 + 1
          else
            end_row = start_row + 1
          end

          if end_row > line_count then
            end_row = line_count
          end

          if start_row < end_row then
            render_range(buf, start_row, end_row)
          end
        end
        cursor_refresh(buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf,
    callback = function()
      buffer_cache[buf] = nil
      hidden_extmarks[buf] = nil
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "InsertLeave" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      cursor_refresh(buf)
    end,
  })
end

---Setup math conceal rendering
---@param opts table?
---@param lang "latex" | "typst"
function M.setup(opts, lang)
  opts = opts or {}
  local conceal = opts.conceal or {}
  local file_lang = utils.lang_to_ft(lang)
  local parser_lang = utils.lang_to_lt(lang)

  local query_string_parts = {}
  for _, name in ipairs(conceal) do
    local q = queries[parser_lang]["conceal_" .. name]
    if q then
      table.insert(query_string_parts, q)
    end
  end
  local query_string = table.concat(query_string_parts, "\n")

  local ft_group = vim.api.nvim_create_augroup("math-conceal-ft-" .. file_lang, { clear = false })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = ft_group,
    buffer = 0,
    callback = function(ev)
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "nci"
      attach_to_buffer(ev.buf, parser_lang, query_string)
    end,
  })

  if vim.bo.filetype == file_lang then
    attach_to_buffer(vim.api.nvim_get_current_buf(), parser_lang, query_string)
  end
end

return M
