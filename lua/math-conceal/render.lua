local M = {}

local typst_symbols = require("math-conceal.symbols").typst_symbols

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
local query_cache = {}
local decoration_provider_active = false

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

  local hl_cache = setmetatable({}, {
    __index = function(t, key)
      local val = "@" .. key .. "." .. lang
      t[key] = val
      return val
    end,
  })

  local api = vim.api
  local ts = vim.treesitter
  local set_extmark = api.nvim_buf_set_extmark
  local get_cursor = api.nvim_win_get_cursor

  api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      if vim.bo[buf_id].filetype ~= lang then
        return false
      end

      local success, parser = pcall(ts.get_parser, buf_id, lang)
      if not success or not parser then
        return false
      end

      local tree = parser:parse()[1]
      if not tree then
        return false
      end

      local cursor = get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]

      for id, node, metadata in query:iter_captures(tree:root(), buf_id, toprow, botrow) do
        local capture_data = metadata[id] or {}
        local conceal_char = capture_data.conceal or metadata.conceal

        if conceal_char == nil then
          goto continue
        end

        local r1, c1, r2, c2 = node:range()

        local is_cursor_inside = false
        if curr_row >= r1 and curr_row <= r2 then
          if curr_row == r1 and curr_row == r2 then
            if curr_col >= c1 and curr_col < c2 then
              is_cursor_inside = true
            end
          else
            is_cursor_inside = true
          end
        end

        if is_cursor_inside then
          goto continue
        end

        local priority = tonumber(capture_data.priority) or tonumber(metadata.priority) or 100

        local capture_name = query.captures[id] or "text"
        local hl_group = hl_cache[capture_name]

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

  decoration_provider_active = true
end

local function setup_cursor_autocmd(pattern)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    pattern = pattern,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local curr_row = cursor[1] - 1

      if curr_row ~= last_cursor_row then
        vim.cmd("redraw!")
        last_cursor_row = curr_row
      else
        vim.cmd("redraw")
      end
    end,
  })
end

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
