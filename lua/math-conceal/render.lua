--- render.lua - Attachment state tracker and decoration provider for conceal rendering
--- Note: Highlighting is now handled by vim.treesitter.query.set() in loader.lua
--- This module tracks which buffers have conceal enabled via the TreeSitter highlight pipeline
local M = {}

-- Buffer cache: buffer_cache[bufnr] = { langs = {...} }
-- Tracks which languages are enabled for conceal in each buffer
local buffer_cache = {}

-- Window viewport state cache for performance optimization
local win_states = {}

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

-- Cleanup window cache on window close
vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(args)
    local win_id = tonumber(args.match)
    if win_id then
      win_states[win_id] = nil
    end
  end,
})

--- Core rendering logic via Decoration Provider
--- Handles fine-grained cursor detection and conceal rendering
local function setup_decoration_provider()
  vim.api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      local buf_config = buffer_cache[buf_id]
      if not buf_config then
        return false
      end

      local buf_tick = vim.b[buf_id].changedtick

      -- Get or initialize window state
      local state = win_states[win_id]
      if not state then
        state = { tick = -1, top = -1, bot = -1, marks = {} }
        win_states[win_id] = state
      end

      -- Cache hit check: if buffer unchanged and viewport unchanged, use cache
      local is_cache_valid = (state.tick == buf_tick) and (state.top == toprow) and (state.bot == botrow)

      if not is_cache_valid then
        -- Cache miss, recalculate
        state.marks = {}
        state.tick = buf_tick
        state.top = toprow
        state.bot = botrow

        local ok, parser = pcall(vim.treesitter.get_parser, buf_id)
        if not ok or not parser then
          return false
        end

        -- Incremental parse
        pcall(parser.parse, parser)

        -- Iterate all relevant trees (main tree + injected trees)
        -- Use pcall to safely handle potential errors
        local ok_iter = pcall(function()
          parser:for_each_tree(function(tree, language_tree)
            local lang = language_tree:lang()
            local root = tree:root()

            -- Get highlights query for this language
            -- (which now includes our conceal directives from loader.lua)
            local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
            if ok_query and query then
              -- Expand query range for smooth scrolling
              local query_top = math.max(0, toprow - 30)
              local query_bot = botrow + 30

              for id, node, metadata in query:iter_captures(root, buf_id, query_top, query_bot) do
                local capture_data = metadata[id]
                -- Get conceal character from metadata (set by directives in query)
                local conceal_char = (capture_data and capture_data.conceal) or metadata.conceal

                if conceal_char then
                  local r1, c1, r2, c2 = node:range()
                  -- Only cache nodes within viewport
                  if r1 <= botrow and r2 >= toprow then
                    local priority = (capture_data and capture_data.priority) or metadata.priority or 100
                    local hl_group = (capture_data and capture_data.highlight) or metadata.highlight or "Conceal"

                    table.insert(state.marks, {
                      r1,
                      c1,
                      r2,
                      c2, -- [1-4] Position
                      conceal_char, -- [5] Conceal char
                      hl_group, -- [6] Highlight group
                      tonumber(priority), -- [7] Priority
                    })
                  end
                end
              end
            end
          end)
        end)

        if not ok_iter then
          return false
        end
      end

      -- Render phase: fast iteration over pure Lua table and set extmarks
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark

      for _, m in ipairs(state.marks) do
        local r1, c1, r2, c2 = m[1], m[2], m[3], m[4]

        -- Fine-grained control: detect if cursor is inside node
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

--- Register a buffer as having conceal enabled (for tracking purposes)
--- @param buf integer Buffer number
--- @param lang string Tree-sitter language name
function M.register_query(buf, lang, _)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end

  -- Initialize buffer cache
  if not buffer_cache[buf] then
    buffer_cache[buf] = { langs = {} }

    -- Cleanup on buffer delete
    vim.api.nvim_create_autocmd("BufDelete", {
      group = augroup,
      buffer = buf,
      callback = function()
        buffer_cache[buf] = nil
      end,
    })

    -- Trigger redraw on cursor move
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = augroup,
      buffer = buf,
      callback = function()
        vim.api.nvim__redraw({ buf = buf, valid = false })
      end,
    })
  end

  -- Track language
  if not vim.tbl_contains(buffer_cache[buf].langs, lang) then
    table.insert(buffer_cache[buf].langs, lang)
  end
end

--- Unregister a language query from a buffer
--- @param buf integer Buffer number
--- @param lang string Language to unregister
function M.unregister_query(buf, lang)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if buffer_cache[buf] then
    buffer_cache[buf].langs = vim.tbl_filter(function(l)
      return l ~= lang
    end, buffer_cache[buf].langs)
  end
end

--- Check if a buffer has any registered queries
--- @param buf integer Buffer number
--- @return boolean
function M.is_attached(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  return buffer_cache[buf] ~= nil and #buffer_cache[buf].langs > 0
end

--- Get registered languages for a buffer
--- @param buf integer Buffer number
--- @return string[] List of registered language names
function M.get_registered_langs(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if buffer_cache[buf] then
    return buffer_cache[buf].langs
  end
  return {}
end

--- Clear all queries for a buffer
--- @param buf integer Buffer number
function M.clear_buffer(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  buffer_cache[buf] = nil
  -- Invalidate window states for this buffer
  for win_id, _ in pairs(win_states) do
    local ok, win_buf = pcall(vim.api.nvim_win_get_buf, win_id)
    if ok and win_buf == buf then
      win_states[win_id] = nil
    end
  end
end

--- Force refresh rendering for a buffer
--- @param buf integer Buffer number (0 for current)
function M.refresh(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  -- Invalidate cache for all windows showing this buffer
  for win_id, _ in pairs(win_states) do
    local ok, win_buf = pcall(vim.api.nvim_win_get_buf, win_id)
    if ok and win_buf == buf then
      win_states[win_id] = nil
    end
  end
  vim.api.nvim__redraw({ buf = buf, valid = false })
end

--- Setup render engine
function M.setup()
  -- Nothing to configure for now
end

--- Enable the rendering engine (call once)
function M.enable()
  setup_decoration_provider()
end

--- Get namespace ID
--- @return integer
function M.get_ns_id()
  return ns_id
end

return M
