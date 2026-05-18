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
local line_ns_id = vim.api.nvim_create_namespace("math-conceal-render-lines")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

local active_configs = {}

local markdown_expand_nodes = {
  code_span = true,
  collapsed_reference_link = true,
  fenced_code_block = true,
  full_reference_link = true,
  image = true,
  inline_link = true,
  shortcut_link = true,
}

local function get_capture_hl_group(query, capture_id)
  local capture_name = query.captures[capture_id]
  if not capture_name then
    return nil
  end

  local hl_group = "@" .. capture_name
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_group, link = true })
  if ok and next(hl) ~= nil then
    return hl_group
  end
end

local function buf_wins(buf)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      table.insert(wins, win)
    end
  end
  return wins
end

local function redraw_win(win_id, range)
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local redraw = {
    win = win_id,
    valid = true,
    flush = false,
  }

  if range then
    redraw.range = range
  end

  vim.api.nvim__redraw(redraw)
end

local function redraw_buf(buf, range)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local redraw = {
    buf = buf,
    valid = true,
    flush = false,
  }

  if range then
    redraw.range = range
  end

  vim.api.nvim__redraw(redraw)
end

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

local function strip_extends(query_string)
  return query_string:gsub("; extends [^\n]+", "")
end

local function read_query_files(filenames)
  local output = {}

  for _, file_path in ipairs(filenames) do
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

  return table.concat(output, "\n")
end

local function get_runtime_highlights_query(language)
  local files = vim.treesitter.query.get_files(language, "highlights")
  if not files or #files == 0 then
    return ""
  end

  return read_query_files(files)
end

local function make_spec(target_lang, query_string)
  query_string = strip_extends(query_string or "")
  if query_string == "" then
    return
  end

  local query = get_parsed_query(target_lang, query_string)
  if not query then
    return
  end

  return {
    target_lang = target_lang,
    query = query,
  }
end

local function collect_target_parsers(parser, parser_lang, target_lang, parsers)
  if parser_lang == target_lang then
    table.insert(parsers, parser)
  end

  local ok, children = pcall(function()
    return parser:children()
  end)

  if not ok or not children then
    return
  end

  for child_lang, child in pairs(children) do
    collect_target_parsers(child, child_lang, target_lang, parsers)
  end
end

local function get_query_trees(cache, spec)
  local ok = pcall(function()
    cache.parser:parse(true)
  end)

  if not ok then
    return {}
  end

  local parsers = {}
  collect_target_parsers(cache.parser, cache.root_lang, spec.target_lang, parsers)

  local trees = {}
  for _, parser in ipairs(parsers) do
    local parsed = pcall(function()
      parser:parse(true)
    end)

    if parsed then
      for _, tree in ipairs(parser:trees() or {}) do
        table.insert(trees, tree)
      end
    end
  end

  return trees
end

local function get_root_parser_lang(buf, parser_lang)
  if parser_lang == "latex" and vim.bo[buf].filetype == "markdown" then
    return "markdown"
  end

  return parser_lang
end

local function get_buffer_specs(buf, config)
  if config.parser_lang == "latex" and vim.bo[buf].filetype == "markdown" then
    local specs = {}

    local markdown_query = get_runtime_highlights_query("markdown")
    local markdown_spec = make_spec("markdown", markdown_query)
    if markdown_spec then
      table.insert(specs, markdown_spec)
    end

    local markdown_inline_query = get_runtime_highlights_query("markdown_inline")
    local markdown_inline_spec = make_spec("markdown_inline", markdown_inline_query)
    if markdown_inline_spec then
      table.insert(specs, markdown_inline_spec)
    end

    local latex_spec = make_spec("latex", config.query_string)
    if latex_spec then
      table.insert(specs, latex_spec)
    end

    return specs
  end

  local spec = make_spec(config.parser_lang, config.query_string)
  if not spec then
    return {}
  end

  return { spec }
end

local function get_expand_range(spec, node)
  if spec.target_lang ~= "markdown" and spec.target_lang ~= "markdown_inline" then
    return node:range()
  end

  local parent = node:parent()
  while parent do
    if markdown_expand_nodes[parent:type()] then
      return parent:range()
    end
    parent = parent:parent()
  end

  return node:range()
end

local function get_conceal_line_range(node)
  local r1, _, r2, c2 = node:range()
  if r1 == r2 then
    return r1, 0, r1, math.max(c2, 1)
  end

  return r1, 0, r2, math.max(c2, 1)
end

local function position_inside_range(row, col, r1, c1, r2, c2)
  if row < r1 or row > r2 then
    return false
  end

  if r1 == r2 then
    return col >= c1 and col < c2
  end

  return (row == r1 and col >= c1) or (row == r2 and col < c2) or (row > r1 and row < r2)
end

local function sync_line_conceal_marks(buf_id, state, curr_row, curr_col)
  vim.api.nvim_buf_clear_namespace(buf_id, line_ns_id, 0, -1)

  local seen = {}
  local set_extmark = vim.api.nvim_buf_set_extmark

  for _, m in ipairs(state.marks) do
    if m[12] == "line" and not position_inside_range(curr_row, curr_col, m[8], m[9], m[10], m[11]) then
      local key = table.concat({ m[1], m[2], m[3], m[4] }, ":")
      if not seen[key] then
        seen[key] = true
        set_extmark(buf_id, line_ns_id, m[1], m[2], {
          conceal_lines = m[5],
          priority = m[7],
          end_row = m[3],
          end_col = m[4],
          strict = false,
        })
      end
    end
  end
end

---Setup decoration provider for conceal rendering (global, only once)
local function setup_decoration_provider()
  vim.api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      local cache = buffer_cache[buf_id]
      if not cache or not cache.parser or not cache.specs or #cache.specs == 0 then
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
      local is_cache_valid = (state.tick == buf_tick)
        and (state.top == toprow)
        and (state.bot == botrow)
        and (state.version == cache.version)

      if not is_cache_valid then
        -- Cache miss: requery Tree-sitter
        state.marks = {}
        state.tick = buf_tick
        state.top = toprow
        state.bot = botrow
        state.version = cache.version

        -- Incremental parse (use true for full correctness)
        for _, spec in ipairs(cache.specs) do
          local trees = get_query_trees(cache, spec)
          for _, tree in ipairs(trees) do
            local root = tree:root()
            -- Query only visible range + small buffer (30 lines) for smooth scrolling
            local query_top = math.max(0, toprow - 30)
            local query_bot = botrow + 30

            for id, node, metadata in spec.query:iter_captures(root, buf_id, query_top, query_bot) do
              local capture_data = metadata[id]
              local conceal_char = capture_data and capture_data.conceal or metadata.conceal
              local conceal_lines = capture_data and capture_data.conceal_lines or metadata.conceal_lines

              if conceal_lines ~= nil then
                local r1, c1, r2, c2 = get_conceal_line_range(node)
                if r1 <= botrow and r2 >= toprow then
                  local priority = (capture_data and capture_data.priority) or metadata.priority or 100
                  local line = vim.api.nvim_buf_get_lines(buf_id, r1, r1 + 1, false)[1] or ""

                  table.insert(state.marks, {
                    r1,
                    c1,
                    r2,
                    c2, -- [1-4] position
                    conceal_lines, -- [5]
                    nil, -- [6] hl_group
                    tonumber(priority) or 100, -- [7]
                    r1, -- [8]
                    c1, -- [9]
                    r1, -- [10]
                    #line, -- [11]
                    "line", -- [12]
                  })
                end
              elseif conceal_char then
                local r1, c1, r2, c2 = node:range()
                local er1, ec1, er2, ec2 = get_expand_range(spec, node)
                -- Only cache marks within actual viewport
                if r1 <= botrow and r2 >= toprow then
                  local priority = (capture_data and capture_data.priority) or metadata.priority or 100
                  local hl_group = (capture_data and capture_data.highlight)
                    or metadata.highlight
                    or get_capture_hl_group(spec.query, id)
                    or "Conceal"

                  -- Store all rendering data in pure Lua table (array is faster than hash)
                  table.insert(state.marks, {
                    r1,
                    c1,
                    r2,
                    c2, -- [1-4] position
                    conceal_char, -- [5]
                    hl_group, -- [6]
                    tonumber(priority) or 100, -- [7]
                    er1, -- [8]
                    ec1, -- [9]
                    er2, -- [10]
                    ec2, -- [11]
                  })
                end
              end
            end
          end
        end
      end

      -- Render phase: ultra-fast iteration over cached Lua table
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark
      sync_line_conceal_marks(buf_id, state, curr_row, curr_col)

      for _, m in ipairs(state.marks) do
        if m[12] == "line" then
          goto continue
        end

        local r1, c1, r2, c2 = m[8], m[9], m[10], m[11]

        -- Collision detection: check if cursor is inside node
        local is_cursor_inside = position_inside_range(curr_row, curr_col, r1, c1, r2, c2)

        if not is_cursor_inside then
          set_extmark(buf_id, ns_id, m[1], m[2], {
            conceal = m[5],
            hl_group = m[6],
            priority = m[7],
            end_row = m[3],
            end_col = m[4],
            ephemeral = true,
          })
        end

        ::continue::
      end

      return false
    end,
  })
end

---Attach conceal logic to buffer
---@param buf number
---@param config table
local function attach_to_buffer(buf, config)
  local root_lang = get_root_parser_lang(buf, config.parser_lang)
  local specs = get_buffer_specs(buf, config)
  if #specs == 0 then
    return
  end

  local parser = vim.treesitter.get_parser(buf, root_lang)
  if not parser then
    return
  end

  if buffer_cache[buf] then
    buffer_cache[buf].parser = parser
    buffer_cache[buf].root_lang = root_lang
    buffer_cache[buf].specs = specs
    buffer_cache[buf].version = buffer_cache[buf].version + 1
    return
  end

  buffer_cache[buf] = {
    parser = parser,
    root_lang = root_lang,
    specs = specs,
    version = 1,
  }

  parser:register_cbs({
    on_changedtree = function(changes)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        if not changes or vim.tbl_isempty(changes) then
          redraw_buf(buf)
          return
        end

        for _, change in ipairs(changes) do
          local start_row = change[1]
          local end_row = change[4]

          if end_row == 2 ^ 32 - 1 then
            redraw_buf(buf)
          else
            redraw_buf(buf, { start_row, end_row + 1 })
          end
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf,
    callback = function()
      buffer_cache[buf] = nil
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, line_ns_id, 0, -1)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(win) ~= buf then
        return
      end

      local info = vim.fn.getwininfo(win)[1]
      if not info then
        redraw_win(win)
        return
      end

      local top = info.topline - 1
      local bot = info.botline
      redraw_win(win, { top, bot })
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
---@param lang string
function M.attach(buf, lang)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local config = active_configs[lang]
  if not config then
    return
  end

  attach_to_buffer(buf, config)

  for _, win in ipairs(buf_wins(buf)) do
    redraw_win(win)
  end
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
  query_string = strip_extends(query_string)
  active_configs[lang] = {
    file_lang = file_lang,
    parser_lang = parser_lang,
    base_query_string = query_string,
    extra_query_string = "",
    query_string = query_string,
  }

  setup_decoration_provider()

  if vim.bo.filetype == file_lang then
    M.attach(vim.api.nvim_get_current_buf(), lang)
  end
end

function M.update_query(lang, query_string)
  local config = active_configs[lang]
  if not config then
    return
  end

  config.base_query_string = strip_extends(query_string or "")
  config.query_string = config.base_query_string .. "\n" .. (config.extra_query_string or "")
end

function M.update_extra_query(lang, query_string)
  local config = active_configs[lang]
  if not config then
    return
  end

  config.extra_query_string = strip_extends(query_string or "")
  config.query_string = config.base_query_string .. "\n" .. config.extra_query_string
end

return M
