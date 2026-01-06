local M = {}

local latex = require("math-conceal.symbols.latex")
local typst = require("math-conceal.symbols.typst")
local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local decoration_provider_active = false

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

local last_cursor_row = -1

---Using neovim internal redraw function to force redraw of a specific line
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
    cursor = true, -- redraw cursor position as well (neovim even set it to false by default)
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
  -- Batch collect conceal files for both languages
  for _, name in ipairs(names) do
    name = "conceal_" .. name
    local conceal_querys = queries[language][name]
    if conceal_querys then
      table.insert(output, conceal_querys)
    end
  end
  return table.concat(output, "\n")
end

---Setup decoration provider for conceal rendering
---Using space to trade for time, caching a lot of parsing results to improve rendering efficiency, including:
---1. Parser per buffer
---2. Syntax tree per buffer
---3. Cursor position based render cache per buffer
---More optimization can be done in the future if needed
---@param lang "latex" | "typst"
---@param query_string string
local function setup_decoration_provider(lang, query_string)
  if decoration_provider_active then
    return
  end

  local query = get_parsed_query(lang, query_string)
  if not query then
    return
  end

  local api = vim.api
  local ts = vim.treesitter
  local set_extmark = api.nvim_buf_set_extmark
  local get_cursor = api.nvim_win_get_cursor
  local bo = vim.bo

  local parser_cache = {}
  local tree_cache = {}
  local hl_cache = {}
  local captures = query.captures

  local extmark_opts = {
    end_row = 0,
    end_col = 0,
    conceal = "",
    ephemeral = true,
    hl_group = "",
    priority = 100,
  }

  local render_cache = {}

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
      local r1, r2 = m[1], m[3]
      for row = r1, r2 do
        if not row_index[row] then
          row_index[row] = {}
        end
        table.insert(row_index[row], i)
      end
    end
    return row_index
  end

  local function get_candidate_marks(row_index, curr_row)
    return row_index[curr_row] or {}
  end

  local function render_mark(buf_id, m)
    extmark_opts.end_row = m[3]
    extmark_opts.end_col = m[4]
    extmark_opts.conceal = m[5]
    extmark_opts.hl_group = m[6]
    extmark_opts.priority = m[7]
    set_extmark(buf_id, ns_id, m[1], m[2], extmark_opts)
  end

  api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      if bo[buf_id].filetype ~= lang then
        return false
      end

      local parser = parser_cache[buf_id]
      if not parser then
        local success, p = pcall(ts.get_parser, buf_id, lang)
        if not success or not p then
          return false
        end
        parser = p
        parser_cache[buf_id] = parser
        parser:register_cbs({
          on_changedtree = function()
            tree_cache[buf_id] = nil
            render_cache[buf_id] = nil
          end,
        })
      end

      local tree = tree_cache[buf_id]
      if not tree then
        local trees = parser:parse()
        tree = trees and trees[1]
        if not tree then
          return false
        end
        tree_cache[buf_id] = tree
      end

      local cursor = get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]

      local cache = render_cache[buf_id]

      if cache and cache.toprow == toprow and cache.botrow == botrow then
        local marks = cache.marks
        local row_index = cache.row_index

        -- Only check marks on cursor's row
        local cursor_candidates = get_candidate_marks(row_index, curr_row)
        local skip_set = {}

        for _, idx in ipairs(cursor_candidates) do
          local m = marks[idx]
          if cursor_in_node(curr_row, curr_col, m[1], m[2], m[3], m[4]) then
            skip_set[idx] = true
          end
        end

        -- Render all marks except those under cursor
        for i = 1, #marks do
          if not skip_set[i] then
            render_mark(buf_id, marks[i])
          end
        end

        return true
      end

      -- Cache miss: rebuild from scratch
      local root = tree:root()
      local marks = {}
      local n = 0

      for id, node, metadata in query:iter_captures(root, buf_id, toprow, botrow + 1) do
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
          marks[n] = { r1, c1, r2, c2, conceal_char, hl_group, priority }

          if not cursor_in_node(curr_row, curr_col, r1, c1, r2, c2) then
            render_mark(buf_id, marks[n])
          end
        end
      end

      local row_index = build_row_index(marks)

      render_cache[buf_id] = {
        toprow = toprow,
        botrow = botrow,
        marks = marks,
        row_index = row_index,
      }

      return true
    end,
  })

  api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    callback = function(ev)
      local buf = ev.buf
      parser_cache[buf] = nil
      tree_cache[buf] = nil
      render_cache[buf] = nil
    end,
  })

  decoration_provider_active = true
end

local function setup_cursor_autocmd(filetypes)
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = filetypes,
    callback = function()
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = augroup,
        buffer = 0,
        callback = function()
          local cursor = vim.api.nvim_win_get_cursor(0)
          local curr_row = cursor[1] - 1

          if curr_row ~= last_cursor_row then
            -- vim.cmd("redraw!")
            redraw_line(0, last_cursor_row)
            redraw_line(0, curr_row)
            last_cursor_row = curr_row
          else
            redraw_line(0, curr_row)
          end
        end,
      })
    end,
  })
end

---Setup math conceal rendering for Typst files
---@param opts MathConcealOptions?
function M.setup(opts)
  opts = opts or {}

  local langs = opts.render.enable
  local pattern = opts.ft
  local conceal = opts.conceal or {}

  for _, lang in ipairs(langs) do
    local query_string = get_conceal_query(lang, conceal)
    setup_decoration_provider(lang, query_string)
  end

  setup_cursor_autocmd(pattern)

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = pattern,
    callback = function()
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "nci"
    end,
  })
end

return M
