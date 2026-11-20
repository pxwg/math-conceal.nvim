---realization of fine grained math conceal rendering using neovim decoration provider API
---only expand conceal when the cursor is under the math node
local M = {}
local native_conceal = require("math-conceal.native-conceal")
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
local win_cursors = {}
local range_cache_limit = 64
local viewport_margin = 30

local ns_id = vim.api.nvim_create_namespace("math-conceal-render")
local line_ns_id = vim.api.nvim_create_namespace("math-conceal-render-lines")
-- Neovim 0.13 wraps at the width of persistent extmark conceal; ephemeral conceal is not measured.
-- Its conceal provider protocol asks for a row's conceal before measuring or drawing the row.
local persistent_conceal = vim.fn.has("nvim-0.13") == 1
  and type(vim.api.nvim__ns_set) == "function"
  and type(vim.api.nvim__buf_set_conceal_provider) == "function"
-- Window conceal surfaces: persistent marks owned by (winid, bufnr) in window-scoped namespaces.
local surfaces = {}
local free_surface_namespaces = {}
local surface_namespace_count = 0
local drawing_surfaces = {}
local EMPTY = {}
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

local function release_surface(win, buf)
  local surface = surfaces[win]
  if not surface or (buf ~= nil and surface.buf ~= buf) then
    return
  end
  surfaces[win] = nil
  drawing_surfaces[win] = nil
  if vim.api.nvim_buf_is_valid(surface.buf) then
    vim.api.nvim_buf_clear_namespace(surface.buf, surface.ns, 0, -1)
  end
  -- Namespaces cannot be deleted; released surfaces return theirs to the pool.
  free_surface_namespaces[#free_surface_namespaces + 1] = surface.ns
end

local function release_buffer_surfaces(buf)
  for win, surface in pairs(surfaces) do
    if surface.buf == buf then
      release_surface(win, buf)
    end
  end
end

local function acquire_surface(win, buf)
  local surface = surfaces[win]
  if surface and surface.buf == buf then
    return surface
  end
  if surface then
    release_surface(win, surface.buf)
  end
  local ns = table.remove(free_surface_namespaces)
  if not ns then
    surface_namespace_count = surface_namespace_count + 1
    -- environment.lua skips math-conceal namespaces when resolving surrounding color.
    ns = vim.api.nvim_create_namespace("math-conceal-render.surface." .. surface_namespace_count)
  end
  vim.api.nvim__ns_set(ns, { wins = { win } })
  -- checked: rows whose marks match the source and cursor; info: extmark -> installed payload;
  -- cycle: rows and formulas handled in this window's redraw.
  surface = { win = win, buf = buf, ns = ns, checked = {}, info = {} }
  surfaces[win] = surface
  return surface
end

-- Keep access to Neovim's private highlighter registry at this boundary.
local function source_highlighter(buf)
  return vim.treesitter.highlighter.active[buf]
end

local function source_parser(buf, cache)
  local highlighter = source_highlighter(buf)
  if highlighter and highlighter.tree == cache.parser then
    return highlighter.tree
  end
end

local function source_is_valid(buf, cache, top, bot)
  local parser = source_parser(buf, cache)
  return parser ~= nil and parser:is_valid(false, { top, bot + 1 })
end

local function release_source(buf, cache)
  if not cache then
    return
  end
  local owned = cache.owned_highlighter
  cache.owned_highlighter = nil
  if owned and source_highlighter(buf) == owned then
    vim.treesitter.stop(buf)
  end
end

local function release_conceal_provider(buf, cache)
  if cache and cache.conceal_provider then
    cache.conceal_provider = nil
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim__buf_set_conceal_provider, buf, false)
    end
  end
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
      release_source(buf, buffer_cache[buf])
      release_conceal_provider(buf, buffer_cache[buf])
      release_buffer_surfaces(buf)
      window_options.detach(buf, "render")
      native_conceal.detach(buf)
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
      win_cursors[win_id] = nil
      release_surface(win_id)
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
  -- `query.parse` does not register the language on its own; without this a
  -- markdown buffer attaching before its first latex injection parse would
  -- fail to build the math conceal spec entirely.
  pcall(vim.treesitter.language.add, lang)
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

local function get_query_trees(buf, cache, spec)
  local root_parser = source_parser(buf, cache)
  if not root_parser then
    return {}
  end
  local parsers = {}
  collect_target_parsers(root_parser, root_parser:lang(), spec.target_lang, parsers)

  local trees = {}
  for _, parser in ipairs(parsers) do
    -- Range-based parsing can leave holes in the tree indices.
    local parsed = parser:trees() or {}
    local indices = vim.tbl_keys(parsed)
    table.sort(indices)
    for _, index in ipairs(indices) do
      table.insert(trees, parsed[index])
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

---Plugin-owned math specs. Native highlighter specs are late-bound separately.
local function get_buffer_specs(config)
  local spec = make_spec(config.parser_lang, config.query_string)
  if not spec then
    return {}
  end

  return { spec }
end

local function get_expand_range(node)
  local parent = node:parent()
  while parent do
    if markdown_expand_nodes[parent:type()] then
      return parent:range()
    end
    parent = parent:parent()
  end

  return node:range()
end

local function formula_range(node)
  while node do
    local kind = node:type()
    if kind == "math" or kind == "latex_block" or kind == "inline_formula" or kind == "displayed_equation" then
      local row, col, end_row, end_col = node:range()
      return { row = row, col = col, end_row = end_row, end_col = end_col }
    end
    node = node:parent()
  end
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

local function before(ar, ac, br, bc)
  return ar < br or (ar == br and ac < bc)
end

-- In start order, any interval ending before its predecessor is already
-- covered. The remaining ends strictly increase, allowing a lower-bound
-- overlap test without copying or merging the marks themselves.
local function custom_intervals(marks, count)
  local intervals, sorted = {}, true
  for i = 1, count do
    local m, prev = marks[i], marks[i - 1]
    intervals[i] = m
    if prev and before(m[1], m[2], prev[1], prev[2]) then
      sorted = false
    end
  end
  if not sorted then
    table.sort(intervals, function(a, b)
      return before(a[1], a[2], b[1], b[2])
    end)
  end
  local kept = 0
  for i = 1, count do
    local m, prev = intervals[i], intervals[kept]
    if not prev or before(prev[3], prev[4], m[3], m[4]) then
      kept = kept + 1
      intervals[kept] = m
    end
  end
  for i = kept + 1, count do
    intervals[i] = nil
  end
  return intervals
end

local function overlaps_custom(intervals, r1, c1, r2, c2)
  local lo, hi = 1, #intervals + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    local m = intervals[mid]
    if before(r1, c1, m[3], m[4]) then
      hi = mid
    else
      lo = mid + 1
    end
  end
  local m = intervals[lo]
  return m and before(m[1], m[2], r2, c2)
end

local function collect_marks(buf_id, cache, toprow, botrow, display_only)
  local marks = {}
  local group = 0
  local specs = vim.list_extend(vim.list_extend({}, cache.specs), cache.native_specs or {})
  local custom_count, intervals
  for _, spec in ipairs(specs) do
    if not spec.native then
      custom_count = nil
    elseif custom_count == nil then
      custom_count = #marks
    end
    local trees = get_query_trees(buf_id, cache, spec)
    for _, tree in ipairs(trees) do
      group = group + 1
      local root = tree:root()
      -- The default match limit can truncate dense queries differently across ranges.
      for id, node, metadata in spec.query:iter_captures(root, buf_id, toprow, botrow + 1, { match_limit = 4096 }) do
        local capture_data = metadata[id]
        local conceal_char = capture_data and capture_data.conceal or metadata.conceal
        local conceal_lines = capture_data and capture_data.conceal_lines or metadata.conceal_lines
        if spec.native then
          -- Match the native highlighter\'s pattern-before-capture precedence.
          conceal_char = metadata.conceal or (capture_data and capture_data.conceal)
        end

        if spec.native and (conceal_char ~= nil or conceal_lines ~= nil) then
          local range = vim.treesitter.get_range(node, buf_id, capture_data)
          local r1, c1, r2, c2 = range[1], range[2], range[4], range[5]
          intervals = intervals or custom_intervals(marks, custom_count)
          if overlaps_custom(intervals, r1, c1, r2, c2) then
            goto next_capture
          end
        end

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
              group, -- [13] query/tree order
            })
          end
        elseif conceal_char then
          local r1, c1, r2, c2 = node:range()
          local er1, ec1, er2, ec2 = r1, c1, r2, c2
          if capture_data and (capture_data.range or capture_data.offset) then
            local range = vim.treesitter.get_range(node, buf_id, capture_data)
            r1, c1, r2, c2 = range[1], range[2], range[4], range[5]
          end
          if spec.target_lang == "markdown" or spec.target_lang == "markdown_inline" then
            er1, ec1, er2, ec2 = get_expand_range(node)
          end
          -- Keep complete marks, including nodes crossing the requested range.
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
              [13] = group, -- query/tree order
              [14] = not display_only and formula_range(node) or nil,
            })
          end
        end
        ::next_capture::
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
    and source_is_valid(buf_id, cache, toprow, botrow)
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

local function extend_cached_marks(buf_id, cache, state, top, bot)
  local groups = {}
  local group_count = 0
  local function append(marks, first, last)
    for _, mark in ipairs(marks) do
      if mark[1] >= first and mark[1] <= last and mark[1] <= bot and mark[3] >= top then
        local group = mark[13]
        groups[group] = groups[group] or {}
        table.insert(groups[group], mark)
        group_count = math.max(group_count, group)
      end
    end
  end

  -- Assign captures by their start row, preserving order at refill boundaries.
  if top < state.top then
    append(collect_marks(buf_id, cache, top, state.top - 1), 0, state.top - 1)
  end
  append(state.marks, top < state.top and state.top or 0, state.bot)
  if bot > state.bot then
    append(collect_marks(buf_id, cache, state.bot + 1, bot), state.bot + 1, bot)
  end

  local marks = {}
  for group = 1, group_count do
    vim.list_extend(marks, groups[group] or {})
  end
  return marks
end

local function collect_cached_marks(buf_id, cache, toprow, botrow, opts)
  if not source_parser(buf_id, cache) then
    return {}
  end
  local specs, hl = native_conceal.specs(buf_id)
  local changed = cache.highlighter ~= hl or #specs ~= #(cache.native_specs or {})
  for i, spec in ipairs(specs) do
    local old = (cache.native_specs or {})[i]
    changed = changed or not old or old.query ~= spec.query or old.target_lang ~= spec.target_lang
  end
  if changed then
    cache.highlighter = hl
    cache.native_specs = specs
    cache.version = cache.version + 1
    cache.epoch = cache.epoch + 1
    cache.range_cache = {}
    cache.range_cache_order = {}
  end
  local tick = vim.b[buf_id].changedtick
  local version = cache.version
  local win_id = opts and opts.winid

  if type(win_id) == "number" and vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf_id then
    local last_row = vim.api.nvim_buf_line_count(buf_id) - 1
    toprow = math.max(0, math.min(toprow, last_row))
    botrow = math.min(botrow, last_row)
    local state = win_states[win_id]
    if not marks_cover_range(state, buf_id, cache, tick, version, toprow, botrow) then
      local top = math.max(0, toprow - viewport_margin)
      local bot = math.min(last_row, botrow + viewport_margin)
      -- Only prefetch padding already parsed by the native highlighter.
      if not source_is_valid(buf_id, cache, top, bot) then
        top, bot = toprow, botrow
      end
      local overlap_top = state and math.max(top, state.top) or top
      local overlap_bot = state and math.min(bot, state.bot) or bot
      local marks
      if
        overlap_top <= overlap_bot and marks_cover_range(state, buf_id, cache, tick, version, overlap_top, overlap_bot)
      then
        marks = extend_cached_marks(buf_id, cache, state, top, bot)
      end
      if not marks or cache.version ~= version then
        marks = collect_marks(buf_id, cache, top, bot)
      end
      state = { buf = buf_id, cache = cache, tick = tick, version = cache.version, top = top, bot = bot, marks = marks }
      win_states[win_id] = state
    end
    return state.marks
  end

  local key = range_cache_key(tick, version, toprow, botrow)
  cache.range_cache = cache.range_cache or {}
  if cache.range_cache[key] ~= nil and source_is_valid(buf_id, cache, toprow, botrow) then
    return cache.range_cache[key]
  end

  -- The public display range has no environment span. Only window rendering
  -- consumes formula ancestry, which can be expensive on wide syntax trees.
  local marks = collect_marks(buf_id, cache, toprow, botrow, true)
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

local function sync_line_conceal_marks(buf_id, state, curr_row, curr_col, toprow, botrow)
  vim.api.nvim_buf_clear_namespace(buf_id, line_ns_id, 0, -1)

  local seen = {}
  local set_extmark = vim.api.nvim_buf_set_extmark
  local keep_conceal = keep_conceal_under_cursor(buf_id)

  for _, m in ipairs(state.marks) do
    if
      m[12] == "line"
      and mark_overlaps_range(m, toprow, botrow)
      and (keep_conceal or not position_inside_range(curr_row, curr_col, m[8], m[9], m[10], m[11]))
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

-- Persistent surfaces follow Neovim's conceal provider protocol (nvim__buf_set_conceal_provider):
-- Neovim calls `_on_conceal(win, buf, row)` before it measures or draws `row`. A surface writes the
-- row's marks for its window then, once per source generation. Cursor reveal flips only marks whose
-- reveal range covers the old or new cursor row. Environment color is resolved for rows Neovim
-- draws, so a redraw costs work proportional to its repainted rows, not to the viewport.

local function payload_key(kind, r1, c1, r2, c2, value, priority)
  return table.concat({ kind, r1, c1, r2, c2, value, priority }, "\31")
end

local function mark_key(m)
  return payload_key(m[12] or "conceal", m[1], m[2], m[3], m[4], m[5], m[7])
end

-- Formula span key, cached on the mark: marks are immutable within one source state.
local function span_key(m)
  local key = m[15]
  if not key then
    local span = m[14]
    key = table.concat({ span.row, span.col, span.end_row, span.end_col }, ":")
    m[15] = key
  end
  return key
end

-- Row index of one source state: marks overlapping each row, and marks whose reveal range covers it.
local function index_state(state)
  if state.by_row then
    return state
  end
  local by_row, reveal_by_row, disjoint, ordered = {}, {}, {}, {}
  local top, bot = state.top, state.bot
  local function add(index, row, i)
    local list = index[row]
    if not list then
      list = {}
      index[row] = list
    end
    list[#list + 1] = i
  end
  for i, m in ipairs(state.marks) do
    for row = math.max(top, m[1]), math.min(bot, m[3]) do
      local list = by_row[row]
      local prev = list and state.marks[list[#list]]
      ordered[row] = ordered[row] ~= false and (not prev or prev[2] < m[2]) and m[1] == row
      add(by_row, row, i)
    end
    for row = math.max(top, m[8]), math.min(bot, m[10]) do
      local list = reveal_by_row[row]
      local prev = list and state.marks[list[#list]]
      disjoint[row] = disjoint[row] ~= false and (not prev or prev[11] <= m[9]) and m[8] == m[10]
      add(reveal_by_row, row, i)
    end
  end
  state.disjoint, state.ordered = disjoint, ordered
  state.by_row, state.reveal_by_row = by_row, reveal_by_row
  return state
end

local function revealed(cursor, m)
  return not cursor.keep and position_inside_range(cursor.row, cursor.col, m[8], m[9], m[10], m[11])
end

---Highlight group for a conceal mark. With `frame`, environment color is resolved once per formula.
---Without it the mark keeps its plain group until a redraw of its row resolves the color.
local function formula_group(surface, m, frame)
  if m[12] == "line" then
    return nil
  end
  local span = m[14]
  if not span or not surface.inherit or not frame then
    return m[6]
  end
  local key = span_key(m)
  local group = frame.spans[key]
  if group == nil then
    local environment = require("math-conceal.environment")
    group = environment.group(environment.resolve(surface.buf, surface.win, span)) or false
    frame.spans[key] = group
  end
  return group or m[6]
end

local function surface_set(surface, m, group, id)
  local line = m[12] == "line"
  id = vim.api.nvim_buf_set_extmark(surface.buf, surface.ns, m[1], m[2], {
    id = id,
    end_row = m[3],
    end_col = m[4],
    conceal = not line and m[5] or nil,
    conceal_lines = line and m[5] or nil,
    hl_group = group,
    priority = m[7],
    invalidate = true,
    strict = false,
  })
  surface.info[id] = { kind = m[12] or "conceal", value = m[5], priority = m[7], group = group or false }
  return id
end

local function surface_del(surface, id)
  vim.api.nvim_buf_del_extmark(surface.buf, surface.ns, id)
  surface.info[id] = nil
end

-- Key of an installed extmark at its current position, which edits may have moved.
local function extmark_key(surface, extmark)
  local info, details = surface.info[extmark[1]], extmark[4]
  return info
    and not details.invalid
    and payload_key(
      info.kind,
      extmark[2],
      extmark[3],
      details.end_row or extmark[2],
      details.end_col or extmark[3],
      info.value,
      info.priority
    )
end

local function row_extmarks(surface, row, to_end)
  return vim.api.nvim_buf_get_extmarks(
    surface.buf,
    surface.ns,
    { row, 0 },
    to_end and { -1, -1 } or { row, -1 },
    { details = true, overlap = true }
  )
end

-- Whether extmark `id`, starting where `m` starts, carries `m`'s payload. Extmarks starting at one
-- position with one payload are interchangeable for the surface.
local function carries(surface, id, m)
  local info = surface.info[id]
  return info ~= nil and info.kind == (m[12] or "conceal") and info.value == m[5] and info.priority == m[7]
end

-- The installed extmark of mark `m`, found at the mark's start.
local function find_extmark(surface, m)
  local pos = { m[1], m[2] }
  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(surface.buf, surface.ns, pos, pos, {})) do
    if carries(surface, extmark[1], m) then
      return extmark[1]
    end
  end
end

---Adopt a source state. Configuration changes invalidate every row; a new coverage drops rows it
---no longer covers, which cursor flips can no longer reach. Edits invalidate rows themselves
---(see surfaces_on_bytes() and surfaces_on_changedtree()).
local function surface_bind(surface, state)
  if surface.state == state then
    return
  end
  local epoch = state.cache.epoch
  if surface.epoch ~= epoch then
    surface.epoch = epoch
    surface.checked = {}
  elseif not surface.state or surface.state.top ~= state.top or surface.state.bot ~= state.bot then
    for row in pairs(surface.checked) do
      if row < state.top or row > state.bot then
        surface.checked[row] = nil
      end
    end
  end
  surface.state = index_state(state)
end

-- Rows below an edit move with their marks; edited rows are measured again.
local function surfaces_on_bytes(buf, start_row, old_rows, new_rows)
  local delta = new_rows - old_rows
  for _, surface in pairs(surfaces) do
    if surface.buf == buf then
      local checked = {}
      for row in pairs(surface.checked) do
        if row < start_row then
          checked[row] = true
        elseif row > start_row + old_rows then
          checked[row + delta] = true
        end
      end
      surface.checked = checked
    end
  end
end

-- Rows whose syntax changed are measured again.
local function surfaces_on_changedtree(buf, changes)
  for _, surface in pairs(surfaces) do
    if surface.buf == buf then
      for row in pairs(surface.checked) do
        for _, range in ipairs(changes) do
          local erow = #range == 6 and range[4] or range[3]
          if row >= range[1] and row <= erow then
            surface.checked[row] = nil
            break
          end
        end
      end
    end
  end
end

---Write row `row`: keep extmarks that still match a desired mark, delete the rest, add the missing.
local function reconcile_row(surface, row, frame)
  local state = surface.state
  local last = row == vim.api.nvim_buf_line_count(surface.buf) - 1
  local installed = row_extmarks(surface, row, last)
  if state.ordered[row] then
    -- Each desired start is unique. Consume installed marks in marktree order,
    -- retaining identical extmarks without serializing either side into keys.
    local pos = 1
    for _, i in ipairs(state.by_row[row]) do
      local m = state.marks[i]
      if not revealed(surface.cursor, m) then
        local matched
        while installed[pos] and not before(row, m[2], installed[pos][2], installed[pos][3]) do
          local entry = installed[pos]
          local id, details = entry[1], entry[4]
          if
            not matched
            and entry[2] == row
            and entry[3] == m[2]
            and not details.invalid
            and details.end_row == m[3]
            and details.end_col == m[4]
            and carries(surface, id, m)
          then
            matched = id
          else
            surface_del(surface, id)
          end
          pos = pos + 1
        end
        local group = formula_group(surface, m, frame)
        if not matched or (frame and (group or false) ~= surface.info[matched].group) then
          surface_set(surface, m, group, matched)
        end
      end
    end
    for i = pos, #installed do
      surface_del(surface, installed[i][1])
    end
    surface.checked[row] = true
    return
  end
  local desired, order = {}, {}
  for _, i in ipairs(state.by_row[row] or EMPTY) do
    local m = state.marks[i]
    if not revealed(surface.cursor, m) then
      local key = mark_key(m)
      if not desired[key] then
        desired[key] = m
        order[#order + 1] = key
      end
    end
  end
  -- Deleted text leaves invalidated marks where it was; past the last row no row ever measures them.
  for _, extmark in ipairs(installed) do
    local id = extmark[1]
    local key = extmark_key(surface, extmark)
    local m = key and desired[key]
    if m then
      desired[key] = false
      if frame and m[12] ~= "line" then
        local group = formula_group(surface, m, frame)
        if (group or false) ~= surface.info[id].group then
          surface_set(surface, m, group, id)
        end
      end
    else
      surface_del(surface, id)
    end
  end
  for _, key in ipairs(order) do
    local m = desired[key]
    if m then
      surface_set(surface, m, formula_group(surface, m, frame))
    end
  end
  surface.checked[row] = true
end

-- A drawn row whose marks are current: only its environment colors can change. Formula marks are
-- matched to the row's extmarks by start column and payload.
local function refresh_row(surface, row, frame)
  local state = surface.state
  -- On a row with unique ascending starts, merge the two ordered streams directly.
  if state.ordered[row] then
    local list = state.by_row[row]
    local pos = 1
    for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(surface.buf, surface.ns, { row, 0 }, { row, -1 }, {})) do
      while list[pos] and state.marks[list[pos]][2] < extmark[3] do
        pos = pos + 1
      end
      local m = state.marks[list[pos]]
      if m and m[2] == extmark[3] and m[14] and m[12] ~= "line" and carries(surface, extmark[1], m) then
        local group = formula_group(surface, m, frame)
        if (group or false) ~= surface.info[extmark[1]].group then
          surface_set(surface, m, group, extmark[1])
        end
      end
    end
    return
  end
  local by_col
  for _, i in ipairs(state.by_row[row] or EMPTY) do
    local m = state.marks[i]
    if m[14] and m[12] ~= "line" and m[1] == row then
      by_col = by_col or {}
      local list = by_col[m[2]]
      if not list then
        list = {}
        by_col[m[2]] = list
      end
      list[#list + 1] = m
    end
  end
  if not by_col then
    return
  end
  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(surface.buf, surface.ns, { row, 0 }, { row, -1 }, {})) do
    local id = extmark[1]
    for _, m in ipairs(by_col[extmark[3]] or EMPTY) do
      if carries(surface, id, m) then
        local group = formula_group(surface, m, frame)
        if (group or false) ~= surface.info[id].group then
          surface_set(surface, m, group, id)
        end
        break
      end
    end
  end
end

local function mark_rows_checked(surface, m)
  local state = surface.state
  for row = math.max(state.top, m[1]), math.min(state.bot, m[3]) do
    if surface.checked[row] then
      return true
    end
  end
  return false
end

---Move the surface's cursor: only marks whose reveal range covers the old or new cursor row can flip.
local function surface_flip(surface, cursor)
  local old = surface.cursor
  surface.cursor = cursor
  if old and old.row == cursor.row and old.col == cursor.col and old.keep == cursor.keep then
    return
  end
  local state = surface.state
  if not state or not old then
    return
  end
  local frame = surface.cycle or { spans = {} }
  local function flip(i, inside)
    local m = state.marks[i]
    if mark_rows_checked(surface, m) then
      local id = find_extmark(surface, m)
      if inside and id then
        surface_del(surface, id)
      elseif not inside and not id then
        surface_set(surface, m, formula_group(surface, m, frame))
      end
    end
  end
  local function visit(point, other, inside)
    if point.keep then
      return
    end
    local list = state.reveal_by_row[point.row] or EMPTY
    if state.disjoint[point.row] then
      -- Lower bound on exclusive ends. At most one interval can contain the point.
      local lo, hi = 1, #list + 1
      while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if state.marks[list[mid]][11] <= point.col then
          lo = mid + 1
        else
          hi = mid
        end
      end
      local i = list[lo]
      if i and revealed(point, state.marks[i]) and not revealed(other, state.marks[i]) then
        flip(i, inside)
      end
    else
      for _, i in ipairs(list) do
        if revealed(point, state.marks[i]) and not revealed(other, state.marks[i]) then
          flip(i, inside)
        end
      end
    end
  end
  visit(old, cursor, false)
  visit(cursor, old, true)
end

local function window_cursor(win, buf)
  local cursor = vim.api.nvim_win_get_cursor(win)
  return { row = cursor[1] - 1, col = cursor[2], keep = keep_conceal_under_cursor(buf) }
end

---Current-generation source state of the surface's window covering `row`. With `extend`, a row
---next to the coverage extends it and a distant row recenters it; without, nothing is collected.
local function surface_state(surface, cache, row, extend)
  local buf, win = surface.buf, surface.win
  local state = win_states[win]
  local current = state
    and state.buf == buf
    and state.cache == cache
    and state.tick == vim.api.nvim_buf_get_changedtick(buf)
    and state.version == cache.version
  if current and row >= state.top and row <= state.bot then
    return state
  end
  if not extend then
    return current and state or nil
  end
  -- Extend coverage only over parsed rows: unparsed rows give no padding, so extending row by row
  -- would requery the whole coverage each time. Such a row keeps its marks, which moved with the
  -- text; on_win collects the viewport, and parsing that changes the tree starts a new generation.
  if not source_is_valid(buf, cache, row, row) then
    return nil
  end
  local top, bot = row, row
  if current and row >= state.top - viewport_margin and row <= state.bot + viewport_margin then
    top, bot = math.min(state.top, row), math.max(state.bot, row)
  end
  collect_cached_marks(buf, cache, top, bot, { winid = win })
  state = win_states[win]
  if state and state.buf == buf and row >= state.top and row <= state.bot then
    return state
  end
end

local function attached_surface(win, buf)
  local surface = surfaces[win]
  if surface and surface.buf == buf then
    return surface
  end
  local cache = buffer_cache[buf]
  if not cache or not cache.parser or not cache.specs or not source_parser(buf, cache) then
    return nil
  end
  surface = acquire_surface(win, buf)
  surface.inherit = cache.inherit_environment_color ~= false
  surface.cursor = window_cursor(win, buf)
  return surface
end

-- Reflow can expose rows beyond the range parsed for the original viewport.
-- Request those rows together, outside redraw, then repeat the measurement
-- once the native parser has covered them.
local function parse_exposed_rows(win, buf, cache, row)
  local pending = cache.pending_parse
  if not pending then
    pending = {}
    cache.pending_parse = pending
  end
  if pending[win] then
    return
  end
  pending[win] = true
  vim.schedule(function()
    pending[win] = nil
    if buffer_cache[buf] ~= cache or not valid_buf_window(buf, win) then
      return
    end
    local parser = source_parser(buf, cache)
    local stop = math.min(vim.api.nvim_buf_line_count(buf), row + vim.api.nvim_win_get_height(win))
    if not parser or row >= stop then
      return
    end
    pending[win] = true
    parser:parse({ row, stop }, function(err)
      pending[win] = nil
      if
        not err
        and buffer_cache[buf] == cache
        and valid_buf_window(buf, win)
        and source_is_valid(buf, cache, row, row)
      then
        redraw_win(win, { row, stop })
      end
    end)
  end)
end

---`_on_conceal` / `_on_conceal_line`: Neovim is about to measure or draw `row` of `win`.
local function on_conceal(_, win, buf, row)
  if not surfaces[win] and not buffer_cache[buf] then
    return
  end
  local surface = attached_surface(win, buf)
  local cache = surface and buffer_cache[buf]
  if not cache then
    return
  end
  local state = surface_state(surface, cache, row, true)
  if not state then
    parse_exposed_rows(win, buf, cache, row)
    return
  end
  surface_bind(surface, state)
  local frame = surface.cycle
  if not surface.checked[row] then
    -- An edited row is rebuilt from the reparsed tree only: tree-sitter reports no changed range for
    -- nodes an edit already collapsed, so marks built from the edited tree would never be corrected.
    if source_is_valid(buf, cache, row, row) then
      reconcile_row(surface, row, frame)
    else
      parse_exposed_rows(win, buf, cache, row)
    end
  elseif frame and surface.inherit and not frame.rows[row] then
    refresh_row(surface, row, frame)
  end
  if frame then
    frame.rows[row] = true
  end
end

---Setup decoration provider for conceal rendering (global, only once)
local function setup_decoration_provider()
  vim.api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, win_id, buf_id, toprow, botrow)
      local surface = surfaces[win_id]
      if surface and surface.buf ~= buf_id then
        -- The window now shows another buffer; retire the previous owner's surface.
        release_surface(win_id, surface.buf)
      end
      local cache = buffer_cache[buf_id]
      if not cache or not cache.parser or not cache.specs then
        return false
      end

      if not source_parser(buf_id, cache) then
        if persistent_conceal then
          release_surface(win_id, buf_id)
        else
          vim.api.nvim_buf_clear_namespace(buf_id, line_ns_id, 0, -1)
        end
        return false
      end
      collect_cached_marks(buf_id, cache, toprow, botrow, { winid = win_id })
      local state = win_states[win_id]

      if persistent_conceal then
        local surface = attached_surface(win_id, buf_id)
        if not surface or not state then
          return false
        end
        surface.inherit = cache.inherit_environment_color ~= false
        surface_bind(surface, state)
        -- Cursor moves without CursorMoved (other windows, programmatic) flip here.
        surface_flip(surface, window_cursor(win_id, buf_id))
        surface.cycle = { spans = {}, rows = {} }
        drawing_surfaces[win_id] = surface
        -- Rows _on_conceal may not reach this frame ('nowrap' skips rows without marks).
        for row = math.max(toprow, state.top), math.min(botrow, state.bot) do
          if not surface.checked[row] and source_is_valid(buf_id, cache, row, row) then
            reconcile_row(surface, row, surface.cycle)
          end
        end
        return false
      end

      local cursor = vim.api.nvim_win_get_cursor(win_id)
      local curr_row = cursor[1] - 1
      local curr_col = cursor[2]
      local keep_conceal = keep_conceal_under_cursor(buf_id)
      -- on_win can precede CursorMoved; leave the previous reveal ranges intact.
      if not win_cursors[win_id] or win_cursors[win_id].buf ~= buf_id then
        win_cursors[win_id] = { buf = buf_id, row = curr_row, col = curr_col, keep = keep_conceal }
      end

      -- Render phase: ultra-fast iteration over cached Lua table
      local set_extmark = vim.api.nvim_buf_set_extmark
      sync_line_conceal_marks(buf_id, state, curr_row, curr_col, toprow, botrow)

      local environment = require("math-conceal.environment")
      local environment_groups = {}
      for _, m in ipairs(state.marks) do
        if m[12] == "line" or not mark_overlaps_range(m, toprow, botrow) then
          goto continue
        end

        local r1, c1, r2, c2 = m[8], m[9], m[10], m[11]

        -- Collision detection: check if cursor is inside node
        local is_cursor_inside = position_inside_range(curr_row, curr_col, r1, c1, r2, c2)

        if keep_conceal or not is_cursor_inside then
          local group = m[6]
          local span = m[14]
          if span and cache.inherit_environment_color ~= false then
            local key = table.concat({ span.row, span.col, span.end_row, span.end_col }, ":")
            if environment_groups[key] == nil then
              environment_groups[key] = environment.group(environment.resolve(buf_id, win_id, span)) or false
            end
            group = environment_groups[key] or group
          end
          set_extmark(buf_id, ns_id, m[1], m[2], {
            conceal = m[5],
            hl_group = group,
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
    on_end = function()
      for win_id, surface in pairs(drawing_surfaces) do
        surface.cycle = nil
        drawing_surfaces[win_id] = nil
      end
    end,
    _on_conceal = persistent_conceal and on_conceal or nil,
    _on_conceal_line = persistent_conceal and on_conceal or nil,
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

local function redraw_cursor_changes(buf)
  local win = vim.api.nvim_get_current_win()
  if not valid_buf_window(buf, win) then
    return
  end

  if persistent_conceal then
    -- Flip before Neovim recomputes the cursor screen position from the revealed layout.
    local surface = surfaces[win]
    local cache = buffer_cache[buf]
    if surface and surface.buf == buf and cache then
      local cursor = window_cursor(win, buf)
      local state = surface_state(surface, cache, cursor.row, false)
      if state then
        surface_bind(surface, state)
        surface_flip(surface, cursor)
      else
        -- A stale generation rebuilds every row with this cursor.
        surface.cursor = cursor
      end
    end
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local current = { buf = buf, row = cursor[1] - 1, col = cursor[2], keep = keep_conceal_under_cursor(buf) }
  local previous = win_cursors[win]
  win_cursors[win] = current
  local state = win_states[win]
  local cache = buffer_cache[buf]
  if
    not previous
    or previous.buf ~= buf
    or not state
    or state.buf ~= buf
    or not cache
    or state.cache ~= cache
    or state.tick ~= vim.b[buf].changedtick
    or state.version ~= cache.version
    or not source_is_valid(buf, cache, state.top, state.bot)
  then
    -- Edits or reattachment can invalidate the previous source positions.
    redraw_current_window_for_buf(buf)
    return
  end

  local ranges = {}
  for _, mark in ipairs(state.marks) do
    local before = not previous.keep
      and position_inside_range(previous.row, previous.col, mark[8], mark[9], mark[10], mark[11])
    local after = not current.keep
      and position_inside_range(current.row, current.col, mark[8], mark[9], mark[10], mark[11])
    if before ~= after then
      -- Redraw whole source lines (end-exclusive), including wrapped portions.
      local last = math.max(mark[1] + 1, mark[3] + (mark[4] > 0 and 1 or 0))
      ranges[#ranges + 1] = { mark[1], last }
    end
  end

  table.sort(ranges, function(a, b)
    return a[1] < b[1]
  end)
  local pending
  for _, range in ipairs(ranges) do
    if pending and range[1] <= pending[2] then
      pending[2] = math.max(pending[2], range[2])
    else
      if pending then
        redraw_win(win, pending)
      end
      pending = range
    end
  end
  if pending then
    redraw_win(win, pending)
  end
end

---Attach conceal logic to buffer
---@param buf number
---@param config table
local function attach_to_buffer(buf, config)
  local root_lang = get_root_parser_lang(buf, config)
  local specs = get_buffer_specs(config)
  local previous = buffer_cache[buf]
  local highlighter = source_highlighter(buf)
  if highlighter and highlighter.tree:lang() ~= root_lang then
    -- A logical-source change may replace our own highlighter, never a borrowed one.
    if not previous or previous.owned_highlighter ~= highlighter then
      return false
    end
    release_source(buf, previous)
    highlighter = nil
  end

  local parser = highlighter and highlighter.tree or vim.treesitter.get_parser(buf, root_lang)
  if not parser then
    return false
  end

  local owned_highlighter = previous and previous.owned_highlighter
  if not highlighter then
    -- Start once at attachment; Neovim owns visible-range parsing and completion redraws.
    vim.treesitter.start(buf, root_lang)
    highlighter = source_highlighter(buf)
    owned_highlighter = highlighter
  end
  if owned_highlighter ~= highlighter then
    owned_highlighter = nil
  end

  if parser_callbacks[parser] ~= true then
    parser_callbacks[parser] = true
    parser:register_cbs({
      on_changedtree = function(changes)
        local cache = buffer_cache[buf]
        if not cache or cache.parser ~= parser then
          return
        end
        -- The native highlighter requests redraws; we only invalidate consumption caches.
        cache.version = cache.version + 1
        cache.range_cache = {}
        cache.range_cache_order = {}
        surfaces_on_changedtree(buf, changes)
      end,
    }, true)
    parser:register_cbs({
      on_bytes = function(bytes_buf, _, start_row, _, _, old_rows, _, _, new_rows)
        local cache = buffer_cache[bytes_buf]
        if cache and cache.parser == parser then
          surfaces_on_bytes(bytes_buf, start_row, old_rows, new_rows)
        end
      end,
    })
  end

  if buffer_cache[buf] then
    buffer_cache[buf].parser = parser
    buffer_cache[buf].owned_highlighter = owned_highlighter
    buffer_cache[buf].root_lang = root_lang
    buffer_cache[buf].specs = specs
    buffer_cache[buf].inherit_environment_color = config.inherit_environment_color
    buffer_cache[buf].version = buffer_cache[buf].version + 1
    buffer_cache[buf].epoch = buffer_cache[buf].epoch + 1
    buffer_cache[buf].range_cache = {}
    buffer_cache[buf].range_cache_order = {}
    return true
  end

  if persistent_conceal then
    -- Rows are measured concealed before they are drawn; disabled again on detach.
    vim.api.nvim__buf_set_conceal_provider(buf, true)
  end
  buffer_cache[buf] = {
    conceal_provider = persistent_conceal,
    parser = parser,
    owned_highlighter = owned_highlighter,
    root_lang = root_lang,
    specs = specs,
    inherit_environment_color = config.inherit_environment_color,
    version = 1,
    -- Configuration generation: a new epoch invalidates every surface row.
    epoch = 1,
    range_cache = {},
    range_cache_order = {},
  }

  ensure_buffer_cleanup_autocmds(buf)

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      redraw_cursor_changes(buf)
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    buffer = buf,
    callback = function(args)
      if mode_changed_involves_visual(args.match) then
        redraw_cursor_changes(buf)
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
    inherit_environment_color = attach_opts.inherit_environment_color,
  })
  if attach_opts.extra_query_string ~= nil and attach_opts.extra_query_string ~= "" then
    config.query_string = config.query_string .. "\n" .. strip_extends(attach_opts.extra_query_string)
  end

  if not attach_to_buffer(buf, config) then
    return false
  end

  native_conceal.attach(buf)
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

  release_source(buf, buffer_cache[buf])
  release_conceal_provider(buf, buffer_cache[buf])
  release_buffer_surfaces(buf)
  native_conceal.detach(buf)
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
  for win_id, cursor in pairs(win_cursors) do
    if cursor.buf == buf then
      win_cursors[win_id] = nil
    end
  end
end

---True when the Unicode surface uses persistent window-scoped conceal (Neovim 0.13+).
---@return boolean
function M.uses_persistent_conceal()
  return persistent_conceal
end

---Namespace of a window's persistent conceal surface, if one is installed.
---@param win number?
---@return integer?
function M.window_namespace(win)
  if win == 0 or win == nil then
    win = vim.api.nvim_get_current_win()
  end
  return surfaces[win] and surfaces[win].ns
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
  local previous = default_buffer_config
  default_buffer_config = normalize_buffer_config(opts, default_buffer_config)
  if previous.mode ~= default_buffer_config.mode then
    -- Persistent surfaces flip the cursor-reveal policy in their next on_win.
    for win, surface in pairs(surfaces) do
      if not buffer_configs[surface.buf] and valid_buf_window(surface.buf, win) then
        redraw_win(win)
      end
    end
    for win, cursor in pairs(win_cursors) do
      if not buffer_configs[cursor.buf] and valid_buf_window(cursor.buf, win) then
        win_cursors[win] = nil
        redraw_win(win)
      end
    end
  end
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
    win_cursors[win] = nil
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
  if not cache or not cache.parser or not cache.specs then
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
  if not cache or not cache.parser or not cache.specs then
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
