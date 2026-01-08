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
---Structure: { [buf_id] = { [extmark_id] = original_opts } }
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

---Check if cursor is within the range [r1, c1) to [r2, c2)
local function is_cursor_inside(cursor_row, cursor_col, r1, c1, r2, c2)
  return (cursor_row > r1 and cursor_row < r2)
    or (cursor_row == r1 and cursor_row == r2 and cursor_col >= c1 and cursor_col < c2)
    or (cursor_row == r1 and cursor_row < r2 and cursor_col >= c1)
    or (cursor_row > r1 and cursor_row == r2 and cursor_col < c2)
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

  -- Clean up existing conceal extmarks in the target range before re-rendering
  vim.api.nvim_buf_clear_namespace(buf, ns_id, start_row, end_row)

  -- Ensure we have a tree (safe access)
  local trees = cache.parser:trees()
  local tree = trees and trees[1]
  if not tree then
    return
  end
  local root = tree:root()

  -- Prepare cursor info for immediate reveal check
  local cursor = vim.api.nvim_win_get_cursor(0)
  local curr_row, curr_col = cursor[1] - 1, cursor[2]
  local is_active_buf = (vim.api.nvim_get_current_buf() == buf)

  for id, node, metadata in cache.query:iter_captures(root, buf, start_row, end_row) do
    local r1, c1, r2, c2 = node:range()

    -- Optimization: Only create extmarks for nodes that START within our update range
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
          ephemeral = false, -- Persistent extmark
        }

        -- Create the extmark first
        local new_id = vim.api.nvim_buf_set_extmark(buf, ns_id, r1, c1, opts)

        -- If cursor is under this node, immediately delete it to "reveal" it.
        -- We must save it to hidden_extmarks so it can be restored when cursor leaves.
        if is_active_buf and is_cursor_inside(curr_row, curr_col, r1, c1, r2, c2) then
          if not hidden_extmarks[buf] then
            hidden_extmarks[buf] = {}
          end
          hidden_extmarks[buf][new_id] = opts
          vim.api.nvim_buf_del_extmark(buf, ns_id, new_id)
        end
      end
    end
  end
end

---Refresh extmarks visibility based on cursor position
---Mimics latex_concealer.nvim's restore_and_gc logic
local function cursor_refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  if not hidden_extmarks[buf] then
    hidden_extmarks[buf] = {}
  end

  for id, original_opts in pairs(hidden_extmarks[buf]) do
    local r1, c1 = original_opts.row, original_opts.col -- Wait, opts doesn't usually have row/col
    local saved = hidden_extmarks[buf][id]
    if saved then
      local r1, c1, r2, c2 = saved.r1, saved.c1, saved.r2, saved.c2
      if not is_cursor_inside(row, col, r1, c1, r2, c2) then
        -- Restore
        pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, r1, c1, saved.opts)
        hidden_extmarks[buf][id] = nil
      end
    end
  end

  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, { row, 0 }, { row, col }, { details = true })

  for _, m in ipairs(marks) do
    local id, r1, c1, details = m[1], m[2], m[3], m[4]
    local r2 = details.end_row or r1
    local c2 = details.end_col or c1

    if is_cursor_inside(row, col, r1, c1, r2, c2) and not hidden_extmarks[buf][id] then
      -- Save FULL info including position, so we can restore it later
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

      -- Delete the extmark to FORCE reveal
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
            -- Clear potential zombies in this range from hidden_extmarks
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

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
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
