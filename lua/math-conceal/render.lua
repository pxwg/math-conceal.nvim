---realization of fine grained math conceal rendering using neovim decoration provider API
---only expand conceal when the cursor is under the math node
local M = {}
local utils = require("math-conceal.utils")
local window_options = require("math-conceal.window-options")

local latex = utils.init_queries_table("latex")
local typst = utils.init_queries_table("typst")

local queries = {
  latex = latex,
  typst = typst,
}

local query_obj_cache = {}
local buffer_cache = {}
local parser_callbacks = setmetatable({}, { __mode = "k" })
-- Viewport caching: store computed node lists per window
local win_states = {}
local range_cache_limit = 64

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local line_ns_id = vim.api.nvim_create_namespace("math-conceal-render-lines")
local augroup = vim.api.nvim_create_augroup("math-conceal-render", { clear = true })

local active_configs = {}
local default_buffer_config = {
  mode = "edit",
}
local buffer_configs = {}
local buffer_cleanup_autocmds = {}

local markdown_expand_nodes = {
  code_span = true,
  collapsed_reference_link = true,
  fenced_code_block = true,
  full_reference_link = true,
  image = true,
  inline_link = true,
  shortcut_link = true,
}

local function get_capture_hl_group(query, capture_id, lang)
  local capture_name = query.captures[capture_id]
  if not capture_name then
    return nil
  end

  local groups = {}
  if lang and not vim.startswith(capture_name, "_") then
    table.insert(groups, "@" .. capture_name .. "." .. lang)
  end
  table.insert(groups, "@" .. capture_name)

  for _, hl_group in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_group, link = true })
    if ok and next(hl) ~= nil then
      return hl_group
    end
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

local function ensure_buffer_cleanup_autocmds(buf)
  if buffer_cleanup_autocmds[buf] == true or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  buffer_cleanup_autocmds[buf] = true
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      window_options.detach(buf, "render")
      buffer_cache[buf] = nil
      buffer_configs[buf] = nil
      buffer_cleanup_autocmds[buf] = nil
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, line_ns_id, 0, -1)
      end
    end,
  })
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

local function get_root_parser_lang(buf, config)
  if config.root_lang ~= nil then
    return config.root_lang
  end
  if config.parser_lang == "latex" and vim.bo[buf].filetype == "markdown" then
    return "markdown"
  end

  return config.parser_lang
end

local function get_buffer_specs(buf, config)
  local root_lang = get_root_parser_lang(buf, config)
  if config.parser_lang == "latex" and root_lang == "markdown" then
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

local function normalize_buffer_config(opts, base)
  opts = opts or {}
  base = base or default_buffer_config
  local config = vim.tbl_extend("force", base, opts)

  if config.mode ~= "edit" and config.mode ~= "preview" and config.mode ~= "presentation" then
    error("math-conceal: buffer mode must be 'edit', 'preview', or 'presentation'", 3)
  end

  return config
end

local function get_buffer_config(buf)
  return buffer_configs[buf] or default_buffer_config
end

local function is_visual_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode or ""
  return mode == "v" or mode == "V" or mode == "\22"
end

local function mode_changed_involves_visual(match)
  local old_mode, new_mode = tostring(match or ""):match("^([^:]*):(.*)$")
  return is_visual_mode(old_mode) or is_visual_mode(new_mode)
end

local function keep_conceal_under_cursor(buf)
  local mode = get_buffer_config(buf).mode
  if mode == "presentation" and is_visual_mode() then
    return false
  end
  return mode == "preview" or mode == "presentation"
end

local function valid_buf_window(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local ok, win_buf = pcall(vim.api.nvim_win_get_buf, win)
  return ok and win_buf == buf
end

local function collect_marks(buf_id, cache, toprow, botrow)
  local marks = {}
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

            table.insert(marks, {
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
              or get_capture_hl_group(spec.query, id, spec.target_lang)
              or "Conceal"

            -- Store all rendering data in pure Lua table (array is faster than hash)
            table.insert(marks, {
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
  return marks
end

local function marks_cover_range(state, buf_id, cache, tick, version, toprow, botrow)
  return state
    and state.buf == buf_id
    and state.cache == cache
    and state.tick == tick
    and state.version == version
    and state.top <= toprow
    and state.bot >= botrow
    and type(state.marks) == "table"
end

local function range_cache_key(tick, version, toprow, botrow)
  return table.concat({ tostring(tick), tostring(version), tostring(toprow), tostring(botrow) }, ":")
end

local function cache_range_marks(cache, key, marks)
  cache.range_cache = cache.range_cache or {}
  cache.range_cache_order = cache.range_cache_order or {}

  if cache.range_cache[key] == nil then
    cache.range_cache_order[#cache.range_cache_order + 1] = key
  end
  cache.range_cache[key] = marks

  while #cache.range_cache_order > range_cache_limit do
    local evicted = table.remove(cache.range_cache_order, 1)
    cache.range_cache[evicted] = nil
  end
end

local function collect_cached_marks(buf_id, cache, toprow, botrow, opts)
  local tick = vim.b[buf_id].changedtick
  local version = cache.version
  local win_id = opts and opts.winid

  if type(win_id) == "number" and vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf_id then
    local state = win_states[win_id]
    if marks_cover_range(state, buf_id, cache, tick, version, toprow, botrow) then
      return state.marks
    end
  end

  local key = range_cache_key(tick, version, toprow, botrow)
  cache.range_cache = cache.range_cache or {}
  if cache.range_cache[key] ~= nil then
    return cache.range_cache[key]
  end

  local marks = collect_marks(buf_id, cache, toprow, botrow)
  cache_range_marks(cache, key, marks)
  return marks
end

local function display_mark(m)
  if m[12] == "line" then
    return {
      source = "math-conceal",
      kind = "line",
      row = m[1],
      col = m[2],
      end_row = m[3],
      end_col = m[4],
      conceal_lines = m[5],
      priority = m[7],
      expand_range = { m[8], m[9], m[10], m[11] },
    }
  end

  return {
    source = "math-conceal",
    kind = "conceal",
    row = m[1],
    col = m[2],
    end_row = m[3],
    end_col = m[4],
    conceal = m[5],
    hl_group = m[6],
    priority = m[7],
    expand_range = { m[8], m[9], m[10], m[11] },
  }
end

local function mark_overlaps_range(mark, toprow, botrow)
  return mark[1] <= botrow and mark[3] >= toprow
end

local function marks_by_row(raw_marks, toprow, botrow)
  local by_row = {}
  for row = toprow, botrow do
    by_row[row] = {}
  end

  for _, mark in ipairs(raw_marks or {}) do
    local start_row = math.max(toprow, mark[1])
    local end_row = math.min(botrow, mark[3])
    if start_row <= end_row then
      local display = display_mark(mark)
      for row = start_row, end_row do
        by_row[row][#by_row[row] + 1] = display
      end
    end
  end

  return by_row
end

local function sync_line_conceal_marks(buf_id, state, curr_row, curr_col)
  vim.api.nvim_buf_clear_namespace(buf_id, line_ns_id, 0, -1)

  local seen = {}
  local set_extmark = vim.api.nvim_buf_set_extmark
  local keep_conceal = keep_conceal_under_cursor(buf_id)

  for _, m in ipairs(state.marks) do
    if
      m[12] == "line" and (keep_conceal or not position_inside_range(curr_row, curr_col, m[8], m[9], m[10], m[11]))
    then
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
      local is_cache_valid = (state.buf == buf_id)
        and (state.cache == cache)
        and (state.tick == buf_tick)
        and (state.top == toprow)
        and (state.bot == botrow)
        and (state.version == cache.version)

      if not is_cache_valid then
        state.buf = buf_id
        state.cache = cache
        state.tick = buf_tick
        state.top = toprow
        state.bot = botrow
        state.version = cache.version
        state.marks = collect_marks(buf_id, cache, toprow, botrow)
      end

      -- Render phase: ultra-fast iteration over cached Lua table
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local set_extmark = vim.api.nvim_buf_set_extmark
      sync_line_conceal_marks(buf_id, state, curr_row, curr_col)
      local keep_conceal = keep_conceal_under_cursor(buf_id)

      for _, m in ipairs(state.marks) do
        if m[12] == "line" then
          goto continue
        end

        local r1, c1, r2, c2 = m[8], m[9], m[10], m[11]

        -- Collision detection: check if cursor is inside node
        local is_cursor_inside = position_inside_range(curr_row, curr_col, r1, c1, r2, c2)

        if keep_conceal or not is_cursor_inside then
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

local function redraw_current_window_for_buf(buf)
  local win = vim.api.nvim_get_current_win()
  if not valid_buf_window(buf, win) then
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
end

---Attach conceal logic to buffer
---@param buf number
---@param config table
local function attach_to_buffer(buf, config)
  local root_lang = get_root_parser_lang(buf, config)
  local specs = get_buffer_specs(buf, config)
  if #specs == 0 then
    return false
  end

  local parser = vim.treesitter.get_parser(buf, root_lang)
  if not parser then
    return false
  end

  if buffer_cache[buf] then
    buffer_cache[buf].parser = parser
    buffer_cache[buf].root_lang = root_lang
    buffer_cache[buf].specs = specs
    buffer_cache[buf].version = buffer_cache[buf].version + 1
    buffer_cache[buf].range_cache = {}
    buffer_cache[buf].range_cache_order = {}
    return true
  end

  buffer_cache[buf] = {
    parser = parser,
    root_lang = root_lang,
    specs = specs,
    version = 1,
    range_cache = {},
    range_cache_order = {},
  }

  if parser_callbacks[parser] ~= true then
    parser_callbacks[parser] = true
    parser:register_cbs({
      on_changedtree = function(changes)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) or buffer_cache[buf] == nil then
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
  end

  ensure_buffer_cleanup_autocmds(buf)

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      redraw_current_window_for_buf(buf)
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    buffer = buf,
    callback = function(args)
      if mode_changed_involves_visual(args.match) then
        redraw_current_window_for_buf(buf)
      end
    end,
  })

  return true
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

---Attach to a specific buffer.
---@param buf number
---@param lang string|{lang:string?, conceal_lang:string?, root_lang:string?, extra_query_string:string?}
---@return boolean
function M.attach(buf, lang)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end

  local attach_opts = type(lang) == "table" and lang or {}
  local conceal_lang = type(lang) == "string" and lang or attach_opts.conceal_lang or attach_opts.lang
  local active = active_configs[conceal_lang]
  if not active then
    return false
  end

  local config = vim.tbl_extend("force", {}, active, {
    root_lang = attach_opts.root_lang,
  })
  if attach_opts.extra_query_string ~= nil and attach_opts.extra_query_string ~= "" then
    config.query_string = config.query_string .. "\n" .. strip_extends(attach_opts.extra_query_string)
  end

  if not attach_to_buffer(buf, config) then
    return false
  end

  window_options.attach(buf, "render")
  for _, win in ipairs(buf_wins(buf)) do
    redraw_win(win)
  end
  return true
end

---Detach ASCII/Unicode conceal rendering from one buffer.
---@param buf number?
function M.detach(buf)
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  buffer_cache[buf] = nil
  window_options.detach(buf, "render")
  buffer_cleanup_autocmds[buf] = nil
  pcall(vim.api.nvim_clear_autocmds, { group = augroup, buffer = buf })
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_clear_namespace, buf, line_ns_id, 0, -1)
  end
  for win_id, state in pairs(win_states) do
    if state.buf == buf then
      win_states[win_id] = nil
    end
  end
end

---@param buf number?
---@return boolean
function M.is_attached(buf)
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end
  return buffer_cache[buf] ~= nil
end

---Setup math conceal rendering for Typst/Latex files
---@param opts table?
---@param lang "latex" | "typst"
function M.setup(opts, lang)
  opts = opts or {}
  window_options.setup(opts.opt)
  M.set_default_buffer_config(opts.buffer)
  local conceal = opts.conceal or {}
  local parser_lang = utils.lang_to_lt(lang)

  local query_string = get_conceal_query(parser_lang, conceal)
  query_string = strip_extends(query_string)
  active_configs[lang] = {
    parser_lang = parser_lang,
    base_query_string = query_string,
    extra_query_string = "",
    query_string = query_string,
  }

  setup_decoration_provider()
end

---Set the default ASCII/Unicode conceal config used by buffers without overrides.
---@param opts table?
---@return table config
function M.set_default_buffer_config(opts)
  default_buffer_config = normalize_buffer_config(opts, default_buffer_config)
  return vim.deepcopy(default_buffer_config)
end

---Configure ASCII/Unicode conceal behavior for one buffer.
---@param buf number?
---@param opts table?
---@return table config
function M.setup_buffer(buf, opts)
  if type(buf) == "table" then
    opts = buf
    buf = nil
  end

  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    error("math-conceal: invalid buffer " .. tostring(buf), 2)
  end

  local config = normalize_buffer_config(opts, get_buffer_config(buf))
  local previous = buffer_configs[buf]
  if previous ~= nil and vim.deep_equal(previous, config) then
    ensure_buffer_cleanup_autocmds(buf)
    window_options.attach(buf, "render")
    return vim.deepcopy(config)
  end

  buffer_configs[buf] = config
  ensure_buffer_cleanup_autocmds(buf)
  window_options.attach(buf, "render")
  for _, win in ipairs(buf_wins(buf)) do
    redraw_win(win)
  end

  return vim.deepcopy(config)
end

---Return the effective ASCII/Unicode conceal config for one buffer.
---@param buf number?
---@return table config
function M.get_buffer_config(buf)
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  return vim.deepcopy(get_buffer_config(buf))
end

---Return true when a buffer is in presentation mode.
---@param buf number?
---@return boolean
function M.is_presentation_mode(buf)
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  return get_buffer_config(buf).mode == "presentation"
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

function M.collect_display_marks(buf, opts)
  opts = opts or {}
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  local cache = buffer_cache[buf]
  if not cache or not cache.parser or not cache.specs or #cache.specs == 0 then
    return {}
  end

  local toprow = tonumber(opts.toprow) or 0
  local botrow = tonumber(opts.botrow) or toprow
  local marks = collect_cached_marks(buf, cache, toprow, botrow, opts)
  local out = {}
  for _, mark in ipairs(marks) do
    if mark_overlaps_range(mark, toprow, botrow) then
      out[#out + 1] = display_mark(mark)
    end
  end
  return out
end

function M.collect_display_marks_by_row(buf, opts)
  opts = opts or {}
  if buf == 0 or buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end

  local cache = buffer_cache[buf]
  if not cache or not cache.parser or not cache.specs or #cache.specs == 0 then
    return {}
  end

  local toprow = tonumber(opts.toprow) or 0
  local botrow = tonumber(opts.botrow) or toprow
  if botrow < toprow then
    toprow, botrow = botrow, toprow
  end

  local marks = collect_cached_marks(buf, cache, toprow, botrow, opts)
  return marks_by_row(marks, toprow, botrow)
end

return M
