---realization of fine grained math conceal rendering using neovim decoration provider API
---only expand conceal when the cursor is under the math node
local M = {}
local uv = vim.loop

local latex = require("math-conceal.symbols.latex")
local typst = require("math-conceal.symbols.typst")
local utils = require("math-conceal.utils")
local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local buffer_cache = {}
local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = false })

---Safe wrapper for internal redraw
---@param buf number
---@param line number
local function safe_redraw_line(buf, line)
  if line < 0 then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  pcall(vim.api.nvim__redraw, {
    buf = buf,
    range = { line, line + 1 },
    valid = false,
    cursor = false,
  })
end

---Get parsed query object from cache or parse a new one
---@param lang "latex" | "typst"
---@param query_string string
---@return table|nil parsed_query
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
    vim.notify_once("Math-Conceal: Failed to parse query", vim.log.levels.ERROR)
    return nil
  end
end

---Update buffer cache: parse tree and build row-based spatial index
---@param buf number
---@param lang string
---@param query table
local function update_buffer_cache(buf, lang, query)
  local cache = buffer_cache[buf]
  if not cache then
    return
  end
  local parser = cache.parser
  parser:parse(true)
  local trees = parser:trees()
  local tree = trees and trees[1]
  if not tree then
    return
  end
  local root = tree:root()
  local marks_by_row = {}
  for id, node, metadata in query:iter_captures(root, buf, 0, -1) do
    local capture_data = metadata[id]
    local conceal_char = capture_data and capture_data.conceal or metadata.conceal
    if conceal_char then
      local r1, c1, r2, c2 = node:range()
      if not marks_by_row[r1] then
        marks_by_row[r1] = {}
      end
      local priority = (capture_data and capture_data.priority) or metadata.priority or 100
      local hl_group = (capture_data and capture_data.highlight) or metadata.highlight or "Conceal"
      table.insert(marks_by_row[r1], {
        col_start = c1,
        col_end = c2,
        row_end = r2,
        conceal = conceal_char,
        hl_group = hl_group,
        priority = tonumber(priority),
      })
    end
  end
  cache.marks_by_row = marks_by_row
  cache.tree_version = vim.b[buf].changedtick
end

---Setup decoration provider for conceal rendering (global, only once)
local function setup_decoration_provider()
  vim.api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      local cache = buffer_cache[buf_id]
      if not cache or not cache.marks_by_row then
        return false
      end
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark
      local extmark_opts = {
        conceal = "",
        ephemeral = true,
        hl_group = "",
        priority = 100,
        end_row = 0,
        end_col = 0,
      }
      for row = toprow, botrow do
        local marks = cache.marks_by_row[row]
        if marks then
          for _, m in ipairs(marks) do
            local r1, c1, r2, c2 = row, m.col_start, m.row_end, m.col_end
            local is_cursor_inside = false
            if curr_row >= r1 and curr_row <= r2 then
              if r1 == r2 then
                if curr_col >= c1 and curr_col < c2 then
                  is_cursor_inside = true
                end
              else
                if curr_row == r1 and curr_col >= c1 then
                  is_cursor_inside = true
                elseif curr_row == r2 and curr_col < c2 then
                  is_cursor_inside = true
                elseif curr_row > r1 and curr_row < r2 then
                  is_cursor_inside = true
                end
              end
            end
            if not is_cursor_inside then
              extmark_opts.conceal = m.conceal
              extmark_opts.hl_group = m.hl_group
              extmark_opts.priority = m.priority
              extmark_opts.end_row = r2
              extmark_opts.end_col = c2
              set_extmark(buf_id, ns_id, r1, c1, extmark_opts)
            end
          end
        end
      end
      return false
    end,
  })
end

---Attach conceal logic to buffer
---@param buf number
---@param lang string
---@param query_string string
local function attach_to_buffer(buf, lang, query_string)
  if buffer_cache[buf] then
    return
  end
  local query = get_parsed_query(lang, query_string)
  if not query then
    return
  end
  local parser = vim.treesitter.get_parser(buf, lang)
  if not parser then
    return
  end
  buffer_cache[buf] = {
    parser = parser,
    marks_by_row = {},
  }
  update_buffer_cache(buf, lang, query)
  parser:register_cbs({
    on_changedtree = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          update_buffer_cache(buf, lang, query)
          vim.api.nvim__redraw({ buf = buf, valid = false })
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf,
    callback = function()
      buffer_cache[buf] = nil
    end,
  })
  local last_cursor_row = -1
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local curr_row = cursor[1] - 1
      if curr_row ~= last_cursor_row then
        safe_redraw_line(buf, last_cursor_row)
        safe_redraw_line(buf, curr_row)
        last_cursor_row = curr_row
      else
        safe_redraw_line(buf, curr_row)
      end
    end,
  })
end

---Get conceal query string for a given language and list of names
---@param language "latex" | "typst"
---@param names string[]
---@return string conceal_query
local function get_conceal_query(language, names)
  local output = {}
  for _, name in ipairs(names) do
    name = "conceal_" .. name
    local conceal_querys = queries[language][name]
    if conceal_querys then
      table.insert(output, conceal_querys)
    end
  end
  return table.concat(output, "\n")
end

---Setup math conceal rendering for Typst/Latex files
---@param opts table?
---@param lang "latex" | "typst"
function M.setup(opts, lang)
  opts = opts or {}
  local conceal = opts.conceal or {}
  local file_lang = utils.lang_to_ft(lang)
  local parser_lang = utils.lang_to_lt(lang)
  local query_string = get_conceal_query(parser_lang, conceal)
  setup_decoration_provider()
  local ft_group = vim.api.nvim_create_augroup("math-conceal-ft-" .. file_lang, { clear = false })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = ft_group,
    buffer = 0,
    callback = function(ev)
      print("hi")
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
