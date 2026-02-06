---realization of fine grained math conceal rendering using neovim decoration provider API
---only expand conceal when the cursor is under the math node
local M = {}
local _uv = vim.uv
local utils = require("math-conceal.utils")

local latex = utils.init_queries_table("latex")
local typst = utils.init_queries_table("typst")

local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local buffer_cache = {}
local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = false })

local active_configs = {}

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

---Setup decoration provider for conceal rendering (global, only once)
local function setup_decoration_provider()
  vim.api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      local cache = buffer_cache[buf_id]
      if not cache or not cache.parser or not cache.query then
        return false
      end

      -- Ensure tree is up to date (parse is incremental, usually fast)
      cache.parser:parse(true)
      local trees = cache.parser:trees()
      local tree = trees and trees[1]
      if not tree then
        return false
      end
      local root = tree:root()

      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark

      -- Query only in visible range (core optimization: only query toprow to botrow)
      for id, node, metadata in cache.query:iter_captures(root, buf_id, toprow, botrow) do
        local capture_data = metadata[id]
        local conceal_char = capture_data and capture_data.conceal or metadata.conceal

        if conceal_char then
          local r1, c1, r2, c2 = node:range()

          -- Cursor collision detection logic remains the same
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
            local priority = (capture_data and capture_data.priority) or metadata.priority or 100
            local hl_group = (capture_data and capture_data.highlight) or metadata.highlight or "Conceal"

            set_extmark(buf_id, ns_id, r1, c1, {
              conceal = conceal_char,
              hl_group = hl_group,
              priority = tonumber(priority),
              end_row = r2,
              end_col = c2,
              ephemeral = true,
            })
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

  -- Only need to store parser and query, no longer need marks_by_row
  buffer_cache[buf] = {
    parser = parser,
    query = query,
  }

  -- Only need to trigger redraw on tree changes, computation is done in on_win
  parser:register_cbs({
    on_changedtree = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
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

  -- Simple redraw trigger on cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.api.nvim__redraw({ buf = buf, valid = false })
    end,
  })
end

---Get conceal query string for a given language and list of names
---Includes both project-internal queries and Neovim runtime queries
---@param language "latex" | "typst"
---@param names string[]
---@return string conceal_query
local function get_conceal_query(language, names)
  local output = {}

  -- First, add project-internal conceal queries
  for _, name in ipairs(names) do
    name = "conceal_" .. name
    local conceal_querys = queries[language][name]
    if conceal_querys then
      table.insert(output, conceal_querys)
    end
  end

  -- Then, add default Neovim runtime queries
  -- Try to get the default conceal query from Neovim's runtime
  local default_query_files = vim.treesitter.query.get_files(language, "highlights")
  if default_query_files and #default_query_files > 0 then
    for _, file_path in ipairs(default_query_files) do
      -- Skip files that are already in our project
      if not file_path:find("math%-conceal") then
        local file = io.open(file_path, "r")
        if file then
          local content = file:read("*a")
          file:close()
          if content and content ~= "" then
            table.insert(output, content)
          end
        end
      end
    end
  end

  return table.concat(output, "\n")
end

---Attach to a specific buffer
---@param buf number
---@param lang string
function M.attach(buf, lang)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local config = active_configs[lang]
  if not config then
    return
  end

  attach_to_buffer(buf, config.parser_lang, config.query_string)

  vim.api.nvim__redraw({ buf = buf, valid = false })
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
  -- HACK: remove `; extends` from query to avoid unexpected behavior of inheriting Neovim's default queries
  query_string = query_string:gsub("; extends [^\n]+", "")
  active_configs[lang] = {
    file_lang = file_lang,
    parser_lang = parser_lang,
    query_string = query_string,
  }

  setup_decoration_provider()

  if vim.bo.filetype == file_lang then
    M.attach(vim.api.nvim_get_current_buf(), lang)
  end
end

return M
