---realization of fine grained math conceal rendering using neovim decoration provider API
---only expand conceal when the cursor is under the math node
local M = {}
local utils = require("math-conceal.utils")

local latex = utils.init_queries_table("latex")
local typst = utils.init_queries_table("typst")

local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local buffer_cache = {}
-- Viewport caching: store computed node lists per window
local win_states = {}

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

local active_configs = {}

-- Clean up window cache on window close
vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(args)
    local win_id = tonumber(args.match)
    if win_id then
      win_states[win_id] = nil
    end
  end,
})

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
      if not cache or not cache.parser then
        return false
      end

      -- Get current buffer version (changedtick)
      local buf_tick = vim.b[buf_id].changedtick

      -- Get or initialize window state
      local state = win_states[win_id]
      if not state then
        state = { tick = -1, top = -1, bot = -1, marks = {} }
        win_states[win_id] = state
      end

      -- Core optimization: cache hit check
      -- Reuse marks if buffer unchanged AND viewport unchanged
      local is_cache_valid = (state.tick == buf_tick) and (state.top == toprow) and (state.bot == botrow)

      if not is_cache_valid then
        -- Cache miss: requery Tree-sitter
        state.marks = {}
        state.tick = buf_tick
        state.top = toprow
        state.bot = botrow

        -- Incremental parse (use true for full correctness)
        cache.parser:parse(true)

        -- Iterate over all trees (including injected ones like latex in markdown)
        cache.parser:for_each_tree(function(t, language_tree)
          local tree_lang = language_tree:lang()
          local query = cache.queries[tree_lang]

          if query then
            local root = t:root()
            -- Query only visible range + small buffer (30 lines) for smooth scrolling
            local query_top = math.max(0, toprow - 30)
            local query_bot = botrow + 30

            for id, node, metadata in query:iter_captures(root, buf_id, query_top, query_bot) do
              local capture_data = metadata[id]
              local conceal_char = capture_data and capture_data.conceal or metadata.conceal

              if conceal_char then
                local r1, c1, r2, c2 = node:range()
                -- Only cache marks within actual viewport
                if r1 <= botrow and r2 >= toprow then
                  local priority = (capture_data and capture_data.priority) or metadata.priority or 100
                  local hl_group = (capture_data and capture_data.highlight) or metadata.highlight or "Conceal"

                  -- Store all rendering data in pure Lua table (array is faster than hash)
                  table.insert(state.marks, {
                    r1,
                    c1,
                    r2,
                    c2, -- [1-4] position
                    conceal_char, -- [5]
                    hl_group, -- [6]
                    tonumber(priority) or 100, -- [7]
                  })
                end
              end
            end
          end
        end)
      end

      -- Render phase: ultra-fast iteration over cached Lua table
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark

      for _, m in ipairs(state.marks) do
        local r1, c1, r2, c2 = m[1], m[2], m[3], m[4]

        -- Collision detection: check if cursor is inside node
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
          set_extmark(buf_id, ns_id, r1, c1, {
            conceal = m[5],
            hl_group = m[6],
            priority = m[7],
            end_row = r2,
            end_col = c2,
            ephemeral = true,
          })
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
  local query = get_parsed_query(lang, query_string)
  if not query then
    return
  end

  if not buffer_cache[buf] then
    -- Use the buffer's default parser (e.g. "markdown" for md files)
    -- It will automatically handle injections (e.g. "latex" inside md)
    local parser = vim.treesitter.get_parser(buf)
    if not parser then
      return
    end

    buffer_cache[buf] = {
      parser = parser,
      queries = {}, -- Allow multiple queries per buffer (e.g. latex query in markdown)
    }

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

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = augroup,
      buffer = buf,
      callback = function()
        vim.api.nvim__redraw({ buf = buf, valid = false })
      end,
    })
  end

  -- Register the query for this specific language
  buffer_cache[buf].queries[lang] = query
end

---Get conceal query string for a given language and list of names
---@param language string
---@param names string[]
---@return string conceal_query
local function get_conceal_query(language, names)
  local output = {}

  -- For latex and typst, load custom conceal queries
  if language == "latex" or language == "typst" then
    for _, name in ipairs(names) do
      name = "conceal_" .. name
      local conceal_querys = queries[language][name]
      if conceal_querys then
        table.insert(output, conceal_querys)
      end
    end
  end

  -- Load built-in runtime queries for all languages
  local default_query_files = vim.treesitter.query.get_files(language, "highlights")
  if default_query_files and #default_query_files > 0 then
    for _, file_path in ipairs(default_query_files) do
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
---@param langs string|string[] Single language or array of languages to attach
function M.attach(buf, langs)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end

  -- Normalize to array
  if type(langs) == "string" then
    langs = { langs }
  end

  -- Attach all specified languages
  for _, lang in ipairs(langs) do
    local config = active_configs[lang]
    if config then
      attach_to_buffer(buf, config.parser_lang, config.query_string)
    end
  end

  vim.api.nvim__redraw({ buf = buf, valid = false })
end

---Setup math conceal rendering for any language
---@param opts table?
---@param lang string
function M.setup(opts, lang)
  opts = opts or {}
  local conceal = opts.conceal or {}

  -- For latex/typst, use the utility functions
  -- For other languages, use the language name directly as parser language
  local file_lang, parser_lang
  if lang == "latex" or lang == "typst" then
    file_lang = utils.lang_to_ft(lang)
    parser_lang = utils.lang_to_lt(lang)
  else
    -- For other languages, use the language name as-is
    file_lang = lang
    parser_lang = lang
  end

  local query_string = get_conceal_query(parser_lang, conceal)
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
