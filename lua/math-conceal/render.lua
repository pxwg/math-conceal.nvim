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
local function get_conceal_query_string(language, names)
  local output = {}
  for _, name in ipairs(names) do
    local key = "conceal_" .. name
    local q_str = queries[language] and queries[language][key]
    if q_str then
      table.insert(output, q_str)
    end
  end
  return table.concat(output, "\n")
end

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

  local parser_cache = {}
  local tree_cache = {}

  local hl_cache = {}

  api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      if vim.bo[buf_id].filetype ~= lang then
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
          on_changedtree = function(changes, tree)
            tree_cache[buf_id] = nil
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
      local root = tree:root()

      for id, node, metadata in query:iter_captures(root, buf_id, toprow, botrow) do
        local capture_data = metadata[id]

        local conceal_char
        if capture_data then
          conceal_char = capture_data.conceal
        end
        if not conceal_char then
          conceal_char = metadata.conceal
        end

        if not conceal_char then
          goto continue
        end

        local r1, c1, r2, c2 = node:range()

        local is_cursor_inside = false
        if curr_row == r1 then
          if r1 == r2 then
            if curr_col >= c1 and curr_col < c2 then
              is_cursor_inside = true
            end
          else
            if curr_col >= c1 then
              is_cursor_inside = true
            end
          end
        elseif curr_row == r2 then
          -- 多行：尾行
          if curr_col < c2 then
            is_cursor_inside = true
          end
        elseif curr_row > r1 and curr_row < r2 then
          is_cursor_inside = true
        end

        if is_cursor_inside then
          goto continue
        end

        local priority = 100
        if capture_data and capture_data.priority then
          priority = tonumber(metadata.priority)
        elseif metadata.priority then
          priority = tonumber(metadata.priority)
        end

        local capture_name = query.captures[id]
        if not capture_name then
          capture_name = "text"
        end

        local hl_group = hl_cache[capture_name]
        if not hl_group then
          hl_group = "@" .. capture_name .. "." .. lang
          hl_cache[capture_name] = hl_group
        end

        set_extmark(buf_id, ns_id, r1, c1, {
          end_row = r2,
          end_col = c2,
          conceal = conceal_char,
          ephemeral = true,
          hl_group = hl_group,
          priority = priority,
        })

        ::continue::
      end

      return true
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    callback = function(ev)
      local buf = ev.buf
      parser_cache[buf] = nil
      tree_cache[buf] = nil
    end,
  })

  decoration_provider_active = true
end

local function setup_cursor_autocmd(pattern)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    pattern = pattern,
    callback = function(ev)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local curr_row = cursor[1] - 1

      if curr_row ~= last_cursor_row then
        -- vim.cmd("redraw!")
        redraw_line(ev.buf, last_cursor_row)
        redraw_line(ev.buf, curr_row)
        last_cursor_row = curr_row
      else
        vim.cmd("redraw")
      end
    end,
  })
end

---Setup math conceal rendering for Typst files
---@param opts MathConcealOptions?
function M.setup(opts)
  opts = opts or {}

  local lang = opts.lang or "typst"
  local pattern = opts.pattern or ("*." .. (opts.file_extension or "typ"))

  local query_string = get_conceal_query("typst", {
    "greek",
    "script",
    "math",
    "font",
    "delim",
    "phy",
  })

  setup_decoration_provider(lang, query_string)

  setup_cursor_autocmd(pattern)

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = lang,
    callback = function()
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "nci"
    end,
  })
end

return M
