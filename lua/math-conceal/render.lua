local M = {}

local latex = require("math-conceal.symbols.latex")
local typst = require("math-conceal.symbols.typst")
local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local configs = {} -- cache different configs

local parser_cache = {}
local tree_cache = {}
local extmark_cache = {}

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = false })

local last_cursor_row = -1
local last_cursor_col = -1

---HACK: Using neovim internal redraw function to force redraw of a specific line
---neovim 0.10+ only, for older versions, is vim.api.nvim_buf_redraw_lines
---ref: https://github.com/nvim-mini/mini.nvim/blob/43ec250/lua/mini/diff.lua#L1905
---@param line number line number to redraw
local function redraw_line(buf, line)
  if line < 0 then
    return
  end
  vim.api.nvim__redraw({
    buf = buf,
    range = { line, line + 1 },
    valid = false,
    cursor = true,
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
    vim.notify("Math-Conceal: Failed to parse query: " .. tostring(query), vim.log.levels.ERROR)
    return nil
  end
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

local function cursor_in_node(curr_row, curr_col, r1, c1, r2, c2)
  if curr_row < r1 or curr_row > r2 then
    return false
  end
  if r1 == r2 then
    return curr_col >= c1 and curr_col < c2
  end
  if curr_row == r1 then
    return curr_col >= c1
  end
  if curr_row == r2 then
    return curr_col < c2
  end
  return true
end

local function build_row_index(marks)
  local row_index = {}
  for i = 1, #marks do
    local m = marks[i]
    local r1, r2 = m.r1, m.r2
    for row = r1, r2 do
      if not row_index[row] then
        row_index[row] = {}
      end
      table.insert(row_index[row], i)
    end
  end
  return row_index
end

---@param buf_id number
---@param marks table[]
local function render_all_marks(buf_id, marks)
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  for i, m in ipairs(marks) do
    local extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, m.r1, m.c1, {
      end_row = m.r2,
      end_col = m.c2,
      conceal = m.conceal,
      hl_group = m.hl_group,
      priority = m.priority,
    })
    m.extmark_id = extmark_id
  end
end

---@param buf_id number
---@param curr_row number
---@param curr_col number
---@param cache table
local function update_cursor_extmarks(buf_id, curr_row, curr_col, cache)
  local marks = cache.marks
  local row_index = cache.row_index

  local cursor_candidates = row_index[curr_row] or {}
  local under_cursor = {}

  for _, idx in ipairs(cursor_candidates) do
    local m = marks[idx]
    if cursor_in_node(curr_row, curr_col, m.r1, m.c1, m.r2, m.c2) then
      under_cursor[idx] = true
    end
  end

  local prev_candidates = row_index[last_cursor_row] or {}
  local prev_under_cursor = {}

  if last_cursor_row >= 0 then
    for _, idx in ipairs(prev_candidates) do
      local m = marks[idx]
      if cursor_in_node(last_cursor_row, last_cursor_col, m.r1, m.c1, m.r2, m.c2) then
        prev_under_cursor[idx] = true
      end
    end
  end

  for idx in pairs(under_cursor) do
    if not prev_under_cursor[idx] then
      local m = marks[idx]
      if m.extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, buf_id, ns_id, m.extmark_id)
      end
    end
  end

  for idx in pairs(prev_under_cursor) do
    if not under_cursor[idx] then
      local m = marks[idx]
      local extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, m.r1, m.c1, {
        end_row = m.r2,
        end_col = m.c2,
        conceal = m.conceal,
        hl_group = m.hl_group,
        priority = m.priority,
      })
      m.extmark_id = extmark_id
    end
  end
end

---@param buf_id number
---@param config table
local function reparse_and_render(buf_id, config)
  local query = config.query
  local lang = config.lang
  local hl_cache = config.hl_cache
  local captures = query.captures

  local parser = parser_cache[buf_id]
  if not parser then
    local success, p = pcall(vim.treesitter.get_parser, buf_id, lang)
    if not success or not p then
      return
    end
    parser = p
    parser_cache[buf_id] = parser

    parser:register_cbs({
      on_changedtree = function()
        tree_cache[buf_id] = nil
        vim.schedule(function()
          reparse_and_render(buf_id, config)
        end)
      end,
    })
  end

  local trees = parser:parse()
  local tree = trees and trees[1]
  if not tree then
    return
  end
  tree_cache[buf_id] = tree

  local root = tree:root()
  local marks = {}
  local n = 0

  for id, node, metadata in query:iter_captures(root, buf_id, 0, -1) do
    local capture_data = metadata[id]
    local conceal_char = capture_data and capture_data.conceal or metadata.conceal
    if conceal_char then
      local r1, c1, r2, c2 = node:range()

      local priority = capture_data and capture_data.priority or metadata.priority
      priority = priority and tonumber(priority) or 100

      local capture_name = captures[id] or "text"
      local hl_group = hl_cache[capture_name]
      if not hl_group then
        hl_group = "@" .. capture_name .. "." .. lang
        hl_cache[capture_name] = hl_group
      end

      n = n + 1
      marks[n] = {
        r1 = r1,
        c1 = c1,
        r2 = r2,
        c2 = c2,
        conceal = conceal_char,
        hl_group = hl_group,
        priority = priority,
      }
    end
  end

  local row_index = build_row_index(marks)

  extmark_cache[buf_id] = {
    marks = marks,
    row_index = row_index,
  }

  render_all_marks(buf_id, marks)

  local win_id = vim.fn.bufwinid(buf_id)
  if win_id ~= -1 then
    local cursor = vim.api.nvim_win_get_cursor(win_id)
    local curr_row = cursor[1] - 1
    local curr_col = cursor[2]
    update_cursor_extmarks(buf_id, curr_row, curr_col, extmark_cache[buf_id])
    last_cursor_row = curr_row
    last_cursor_col = curr_col
  end
end

---Setup math conceal rendering
---@param filetype string
---@param query_string string
local function setup_rendering(filetype, query_string)
  local query = get_parsed_query(filetype, query_string)
  if not query then
    return
  end

  configs[filetype] = {
    query = query,
    lang = filetype,
    hl_cache = {},
  }
end

local function setup_cursor_autocmd()
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = vim.api.nvim_get_current_buf(),
    callback = function()
      local buf_id = vim.api.nvim_get_current_buf()
      local cache = extmark_cache[buf_id]

      if not cache then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]

      update_cursor_extmarks(buf_id, curr_row, curr_col, cache)

      if curr_row ~= last_cursor_row then
        redraw_line(buf_id, last_cursor_row)
        redraw_line(buf_id, curr_row)
      else
        redraw_line(buf_id, curr_row)
      end

      last_cursor_row = curr_row
      last_cursor_col = curr_col
    end,
  })
end

local function setup_buffer_autocmds(buf_id, config)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    buffer = buf_id,
    once = true,
    callback = function()
      reparse_and_render(buf_id, config)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf_id,
    callback = function()
      parser_cache[buf_id] = nil
      tree_cache[buf_id] = nil
      extmark_cache[buf_id] = nil
    end,
  })
end

---Setup math conceal rendering for files
---@param opts table?
---@param lang "latex" | "typst"
---@param filetype string
function M.setup(opts, lang, filetype)
  opts = opts or {}

  local conceal = opts.conceal or {}

  local query_string = get_conceal_query(lang, conceal)

  setup_rendering(filetype, query_string)

  local buf_id = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf_id].filetype
  local config = configs[ft]

  if config then
    setup_buffer_autocmds(buf_id, config)
    setup_cursor_autocmd()
  end
end

return M
