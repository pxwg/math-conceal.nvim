--- Render dispatch layer for math-conceal.image.
--- Handles adapter-viewport re-rendering (render_buf) and live insert-mode preview
--- (render_live_typst_preview).  Both paths share semantics.classify() and the
--- same extmark/session infrastructure.

local cursor_visibility = require("math-conceal.image.cursor-visibility")
local semantics_mod = require("math-conceal.image.semantics")
local state = require("math-conceal.image.state")
local M = {}

local diagnostics = {}

local PREVIEW_FLOAT_TARGET_RANGE = { 0, 0, 0, 0 }
local PREVIEW_FLOAT_LINE_COUNT = 2

local candidate_bounds_penalty
local candidate_obstacle_penalty
local list_nearby_float_obstacles
local cursor_in_range
local scan_formula_matches

--- Extract the text contained within a buffer range.
--- @param range Range4
--- @param bufnr integer
--- @return string
local function range_to_string(range, bufnr)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local content = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #content == 0 or content[1] == nil then
    return nil
  end
  if start_row == end_row then
    content[1] = string.sub(content[1], start_col + 1, end_col)
  else
    content[1] = string.sub(content[1], start_col + 1)
    content[#content] = string.sub(content[#content], 0, end_col)
  end
  return table.concat(content, "\n")
end

local function clamp_range_to_buffer(bufnr, range)
  return cursor_visibility.get_item_effective_range({ bufnr = bufnr, range = range })
end

local function get_item_effective_range(item)
  return cursor_visibility.get_item_effective_range(item)
end

local function full_line_range(bufnr, row)
  local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false) or { "" })[1] or ""
  return { row, 0, row, #line }
end

local function line_text(bufnr, row)
  return (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false) or { "" })[1] or ""
end

local function trim_right(s)
  return (s or ""):gsub("%s+$", "")
end

local function trim_left(s)
  return (s or ""):gsub("^%s+", "")
end

--- Build an index of query-matched block nodes keyed by TSNode:id().
--- This index is used only for semantic annotation; actual top-level selection
--- is performed by AST traversal with subtree pruning.
--- @param bufnr integer
--- @param tree TSNode
--- @param query vim.treesitter.Query
--- @param start_row integer|nil
--- @param end_row integer|nil
--- @return table<integer, table>
local function build_typst_match_index(bufnr, tree, query, start_row, end_row)
  local index = {}

  for _, match, _ in query:iter_matches(tree, bufnr, start_row, end_row, { all = true }) do
    local block = match[3] and match[3][1]
    if block ~= nil then
      local node_id = block:id()
      local entry = {
        node = block,
        node_type = block:type(),
        range = { block:range() },
      }

      if entry.node_type == "code" then
        local code_node = match[2] and match[2][1]
        entry.code_type = code_node and code_node:type() or nil

        if match[1] ~= nil then
          local a, b, c, d = match[1][1]:range()
          entry.call_ident = range_to_string({ a, b, c, d }, bufnr)
        else
          entry.call_ident = ""
        end
      end

      index[node_id] = entry
    end
  end

  return index
end

local function range_overlaps_rows(range, start_row, end_row)
  return range[3] >= start_row and range[1] <= end_row
end

--- Traverse AST top-down and collect only maximal / top-level matched units.
--- If a node is already a matched block, its subtree is pruned.
--- @param root TSNode
--- @param match_index table<integer, table>
--- @param start_row integer|nil
--- @param end_row integer|nil
--- @return table[]
local function collect_top_level_typst_units(root, match_index, start_row, end_row)
  local units = {}

  local function visit(node)
    if node == nil then
      return
    end
    local sr, _, er, _ = node:range()
    if start_row ~= nil and end_row ~= nil and (er < start_row or sr > end_row) then
      return
    end

    local entry = match_index[node:id()]
    if entry ~= nil then
      if start_row == nil or range_overlaps_rows(entry.range, start_row, end_row) then
        units[#units + 1] = entry
      end
      return
    end

    for child in node:iter_children() do
      if child:named() then
        visit(child)
      end
    end
  end

  visit(root)
  return units
end

local function typst_unit_key(unit)
  local range = unit and unit.range
  if range == nil then
    return nil
  end
  return table.concat({ "typst", unit.node_type or "", range[1], range[2], range[3], range[4] }, ":")
end

local function collect_nested_typst_math_entries(bufnr, parent_unit, query, prelude_count)
  if parent_unit == nil or parent_unit.node == nil or query == nil then
    return {}
  end

  local parent_key = typst_unit_key(parent_unit)
  local match_index =
    build_typst_match_index(bufnr, parent_unit.node, query, parent_unit.range[1], parent_unit.range[3] + 1)
  local entries = {}

  local function visit(node)
    if node == nil then
      return
    end

    local entry = match_index[node:id()]
    if entry ~= nil and entry.node_type == "math" then
      entries[#entries + 1] = {
        range = entry.range,
        prelude_count = prelude_count,
        node_type = "math",
        ts_node = entry.node,
        stable_key = table.concat({ "nested", parent_key or "", tostring(entry.node:id()) }, ":"),
      }
      return
    end

    for child in node:iter_children() do
      if child:named() then
        visit(child)
      end
    end
  end

  for child in parent_unit.node:iter_children() do
    if child:named() then
      visit(child)
    end
  end

  return entries
end

--- Convert top-level units into ordered render entries while accumulating preludes.
--- @param bufnr integer
--- @param units table[]
--- @param opts table|nil
--- @return table[]
local function build_render_entries_from_units(bufnr, units, opts)
  opts = opts or {}
  local render_entries = {}

  for _, unit in ipairs(units) do
    if unit.node_type == "math" then
      render_entries[#render_entries + 1] = {
        range = unit.range,
        prelude_count = #state.runtime_preludes,
        node_type = "math",
        ts_node = unit.node,
      }
    elseif unit.node_type == "code" then
      if vim.list_contains({ "let", "set", "import", "show" }, unit.code_type) then
        local prelude_text = range_to_string(unit.range, bufnr)
        -- Bare `#show: ...` transforms the whole document. Applying it to each
        -- isolated snippet is both expensive in template-heavy projects and
        -- usually not the intended math/code styling. Selector show rules such
        -- as `#show math.equation: ...` are still carried as local context.
        if unit.code_type ~= "show" or not (prelude_text or ""):match("^%s*#%s*show%s*:") then
          state.runtime_preludes[#state.runtime_preludes + 1] = prelude_text .. "\n"
        end
      elseif not vim.list_contains({ "pagebreak" }, unit.call_ident or "") then
        render_entries[#render_entries + 1] = {
          range = unit.range,
          prelude_count = #state.runtime_preludes,
          node_type = "code",
          ts_node = unit.node,
        }
        if opts.progressive_parent_key ~= nil and opts.progressive_parent_key == typst_unit_key(unit) then
          local nested_entries = collect_nested_typst_math_entries(bufnr, unit, opts.query, #state.runtime_preludes)
          for _, nested_entry in ipairs(nested_entries) do
            render_entries[#render_entries + 1] = nested_entry
          end
        end
      end
    end
  end

  return render_entries
end

local function units_overlap_rows(unit, start_row, end_row)
  return range_overlaps_rows(unit.range, start_row, end_row)
end

local function buffer_source_kind(bufnr)
  local ok, main = pcall(require, "math-conceal.image")
  if ok and type(main.source_kind_for_bufnr) == "function" then
    return main.source_kind_for_bufnr(bufnr)
  end

  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr) or ""
  if ft == "typst" or name:match("%.typ$") then
    return "typst"
  elseif ft == "markdown" or name:match("%.md$") or name:match("%.markdown$") then
    return "markdown"
  elseif ft == "tex" or ft == "plaintex" or ft == "latex" or name:match("%.tex$") then
    return "latex"
  end
  return nil
end

local function uses_formula_manager(bufnr, main, project_scope)
  local config = (main and main.config) or {}
  if config.use_formula_service ~= false then
    return true
  end
  if project_scope ~= nil and project_scope.backend_id == "latex" then
    return true
  end
  return buffer_source_kind(bufnr) == "latex"
end

local function get_buffer_parser(bufnr, lang)
  local ok, parser, err = pcall(vim.treesitter.get_parser, bufnr, lang)
  if ok and parser ~= nil then
    return parser, nil
  end
  if ok then
    return nil, err or "parser unavailable"
  end
  return nil, tostring(parser)
end

local max_parser_retries = 20
local parser_retry_base_delay_ms = 25
local parser_retry_max_delay_ms = 250

local function notify_parser_unavailable(bufnr, lang, bs, reason)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    local ok_main, main = pcall(require, "math-conceal.image")
    if not ok_main or main._enabled_buffers[bufnr] ~= true then
      return
    end

    local parser, latest_reason = get_buffer_parser(bufnr, lang)
    if parser ~= nil then
      if bs.parser_retry_counts then
        bs.parser_retry_counts[lang] = nil
      end
      require("math-conceal.image.machine.runtime").render_buf(bufnr)
      return
    end

    if bs.parser_retry_counts then
      bs.parser_retry_counts[lang] = nil
    end
    vim.notify(
      ("[math-conceal.image] %s tree-sitter parser unavailable: %s"):format(lang, tostring(latest_reason or reason)),
      vim.log.levels.WARN
    )
  end)
end

local function schedule_parser_retry(bufnr, lang, bs, reason)
  bs.parser_retry_counts = bs.parser_retry_counts or {}
  local retries = bs.parser_retry_counts[lang] or 0
  if retries >= max_parser_retries then
    notify_parser_unavailable(bufnr, lang, bs, reason)
    return
  end

  bs.parser_retry_counts[lang] = retries + 1
  local delay = math.min(parser_retry_max_delay_ms, parser_retry_base_delay_ms * (retries + 1))
  vim.defer_fn(function()
    local ok_main, main = pcall(require, "math-conceal.image")
    if
      ok_main
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
      and main._enabled_buffers[bufnr] == true
    then
      require("math-conceal.image.machine.runtime").render_buf(bufnr)
    end
  end, delay)
end

local function expand_rows_to_cover_units(units, start_row, end_row)
  local expanded_start = start_row
  local expanded_end = end_row
  local changed = true
  while changed do
    changed = false
    for _, unit in ipairs(units or {}) do
      if units_overlap_rows(unit, expanded_start, expanded_end) then
        if unit.range[1] < expanded_start then
          expanded_start = unit.range[1]
          changed = true
        end
        if unit.range[3] > expanded_end then
          expanded_end = unit.range[3]
          changed = true
        end
      end
    end
  end
  return expanded_start, expanded_end
end

local function can_incrementally_merge_units(prev_units, new_units, start_row, end_row)
  for _, unit in ipairs(prev_units or {}) do
    if units_overlap_rows(unit, start_row, end_row) and unit.node_type ~= "math" then
      return false
    end
  end
  for _, unit in ipairs(new_units or {}) do
    if unit.node_type ~= "math" then
      return false
    end
  end
  return true
end

local function merge_units_in_rows(prev_units, new_units, start_row, end_row)
  local merged = {}
  local inserted = false
  for _, unit in ipairs(prev_units or {}) do
    if unit.range[3] < start_row then
      merged[#merged + 1] = unit
    elseif unit.range[1] > end_row then
      if not inserted then
        for _, new_unit in ipairs(new_units or {}) do
          merged[#merged + 1] = new_unit
        end
        inserted = true
      end
      merged[#merged + 1] = unit
    end
  end
  if not inserted then
    for _, new_unit in ipairs(new_units or {}) do
      merged[#merged + 1] = new_unit
    end
  end
  return merged
end

local function collect_full_units(bufnr, root, query)
  local match_index = build_typst_match_index(bufnr, root, query)
  return collect_top_level_typst_units(root, match_index)
end

local function collect_incremental_units(bufnr, root, query, prev_units, pending_change)
  if prev_units == nil or pending_change == nil or pending_change.requires_full then
    return nil
  end

  local start_row, end_row =
    expand_rows_to_cover_units(prev_units, pending_change.start_row, pending_change.new_end_row)
  local match_index = build_typst_match_index(bufnr, root, query, start_row, end_row + 1)
  local new_units = collect_top_level_typst_units(root, match_index, start_row, end_row)
  if not can_incrementally_merge_units(prev_units, new_units, start_row, end_row) then
    return nil
  end
  return merge_units_in_rows(prev_units, new_units, start_row, end_row)
end

local function clear_diagnostics(bufnr)
  vim.schedule(function()
    vim.diagnostic.reset(state.ns_id, bufnr)
  end)
end

local function hash_string(value)
  return vim.fn.sha256(value or "")
end

local function context_hash(prelude_count)
  local parts = { tostring(prelude_count or 0) }
  for i = 1, prelude_count or 0 do
    parts[#parts + 1] = state.runtime_preludes[i] or ""
  end
  return hash_string(table.concat(parts, "\0"))
end

local function full_render_context_hash(main, project_scope)
  return hash_string(table.concat({
    "full-sidecar-inline-context-v3",
    project_scope.context_signature or project_scope.project_scope_id or "",
    main.config.header or "",
    main._styling_prelude or "",
    tostring(state._cell_px_w or ""),
    tostring(state._cell_px_h or ""),
    tostring(state._render_ppi or main.config.ppi or ""),
  }, "\0"))
end

local function is_insert_like_mode(mode)
  return cursor_visibility.is_insert_like_mode(mode)
end

local function item_has_stable_render(item)
  return item ~= nil and item.page_path ~= nil and item.natural_cols ~= nil and item.natural_rows ~= nil
end

local function cleanup_item(bufnr, item)
  return require("math-conceal.image.apply").cleanup_item(bufnr, item)
end

local function cleanup_preview_image(bufnr, opts)
  return require("math-conceal.image.apply").cleanup_preview_image(bufnr, opts)
end

local function cleanup_preview_item_request(bufnr, item, opts)
  return require("math-conceal.image.apply").cleanup_preview_item_request(bufnr, item, opts)
end

local function get_text_slice(bufnr, start_row, start_col, end_row, end_col)
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    return ""
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if start_row >= line_count or end_row >= line_count then
    return ""
  end
  local ok, result = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, start_col, end_row, end_col, {})
  if not ok then
    return ""
  end
  return table.concat(result, "\n")
end

local function get_math_symbol_span_at_pos(item, row, col)
  local line = vim.fn.getbufline(item.bufnr, row + 1)[1] or ""
  if line == "" then
    return nil
  end

  local parser = vim.treesitter.get_parser(item.bufnr, "typst")
  local root = parser:parse()[1]:root()
  local end_col = math.min(#line, col + 1)
  local node = root:named_descendant_for_range(row, col, row, end_col)
  if node == nil then
    return nil
  end

  local formula_node = nil
  local target = node
  while target ~= nil do
    local t = target:type()
    if t == "formula" then
      formula_node = target
      break
    end
    target = target:parent()
  end
  if formula_node == nil then
    return nil
  end

  target = node
  while target ~= nil do
    local parent = target:parent()
    if parent == nil then
      return nil
    end
    if parent:id() == formula_node:id() then
      break
    end
    target = parent
  end

  local sr, sc, er, ec = target:range()
  if not cursor_in_range(item.range, sr, sc, { include_right_edge = false }) then
    return nil
  end
  if er < sr or (er == sr and ec < sc) then
    return nil
  end
  local text = get_text_slice(item.bufnr, sr, sc, er, ec)
  if text == nil or text == "" or text:match("^%s+$") then
    return nil
  end

  return {
    start_row = sr,
    start_col = sc,
    end_row = er,
    end_col = ec,
    text = text,
  }
end

local function get_math_symbol_span_at_cursor(item, row, col, mode)
  if item == nil or item.node_type ~= "math" or type(item.str) ~= "string" then
    return nil
  end

  local line = vim.fn.getbufline(item.bufnr, row + 1)[1] or ""
  if line == "" then
    return nil
  end

  local candidates = {}
  if col >= 0 and col < #line then
    candidates[#candidates + 1] = col
  end

  if is_insert_like_mode(mode) and col > 0 then
    local left_col = col - 1
    if left_col >= 0 and left_col < #line then
      candidates[#candidates + 1] = left_col
    end
  end

  for _, candidate_col in ipairs(candidates) do
    local span = get_math_symbol_span_at_pos(item, row, candidate_col)
    if span ~= nil then
      return span
    end
  end

  return nil
end

local function preview_item_context_key(item)
  local bstate = state.buffer_render_state[item.bufnr] or {}
  local prelude_chunks = bstate.runtime_preludes or state.runtime_preludes or {}
  local prelude_count = math.max(0, math.min(item.prelude_count or 0, #prelude_chunks))
  local semantics = item.semantics or {}
  local ok_main, main = pcall(require, "math-conceal.image")
  local config = ok_main and main.config or {}
  local parts = {
    "preview-context-v2",
    tostring(prelude_count),
    tostring(item.node_type or ""),
    tostring(semantics.constraint_kind or ""),
    tostring(semantics.display_kind or ""),
    tostring(semantics.render_whole_line == true),
    tostring(state._cell_px_w or ""),
    tostring(state._cell_px_h or ""),
    tostring(state._render_ppi or config.ppi or ""),
    config.header or "",
    (ok_main and main._styling_prelude) or "",
  }
  for i = 1, prelude_count do
    parts[#parts + 1] = prelude_chunks[i] or ""
  end
  return hash_string(table.concat(parts, "\0"))
end

local function preview_render_key(item, source_text, cursor_row, cursor_col, span)
  local parts = {
    "preview-render-v2",
    table.concat(item.range, ":"),
    preview_item_context_key(item),
    tostring(cursor_row),
    tostring(cursor_col),
    source_text,
  }
  if span == nil then
    parts[#parts + 1] = "plain"
  else
    parts[#parts + 1] = tostring(span.start_row)
    parts[#parts + 1] = tostring(span.start_col)
    parts[#parts + 1] = tostring(span.end_row)
    parts[#parts + 1] = tostring(span.end_col)
  end
  return hash_string(table.concat(parts, "\0"))
end

local function make_highlighted_preview_math(item, cursor_row, cursor_col, mode)
  if item == nil or item.node_type ~= "math" then
    return nil, nil, nil
  end

  if item.requires_mitex == true or (item.semantics and item.semantics.markdown_math == true) then
    local source_text = item.source_str or range_to_string(item.range, item.bufnr)
    if type(item.str) ~= "string" or type(source_text) ~= "string" or item.str == "" or source_text == "" then
      return nil, nil, nil
    end
    return item.str, preview_render_key(item, source_text, cursor_row, cursor_col, nil), source_text
  end

  local source_text = range_to_string(item.range, item.bufnr)
  if source_text == nil or source_text == "" then
    return nil, nil, nil
  end

  local span = get_math_symbol_span_at_cursor(item, cursor_row, cursor_col, mode)
  if span == nil then
    local key = preview_render_key(item, source_text, cursor_row, cursor_col, nil)
    return source_text, key, source_text
  end

  if not cursor_in_range(item.range, span.start_row, span.start_col, { include_right_edge = false }) then
    local key = preview_render_key(item, source_text, cursor_row, cursor_col, nil)
    return source_text, key, source_text
  end

  local prefix = get_text_slice(item.bufnr, item.range[1], item.range[2], span.start_row, span.start_col)
  local suffix = get_text_slice(item.bufnr, span.end_row, span.end_col, item.range[3], item.range[4])
  local replacement = "#text(red)[$" .. span.text .. "$];"
  local rendered = prefix .. replacement .. suffix
  local key = preview_render_key(item, source_text, cursor_row, cursor_col, span)
  return rendered, key, source_text
end

cursor_in_range = function(range, row, col, opts)
  return cursor_visibility.cursor_in_range(range, row, col, opts)
end

local function cursor_engages_inline_item(range, row, col, mode)
  return cursor_visibility.cursor_engages_inline_item(range, row, col, mode)
end

local function cursor_near_range(range, row, col)
  if range == nil or row < range[1] or row > range[3] then
    return false
  end

  local slack_cols = 8
  if range[1] == range[3] then
    return col >= math.max(0, range[2] - 1) and col <= math.max(range[4], range[2]) + slack_cols
  end
  if row == range[1] then
    return col >= math.max(0, range[2] - 1)
  end
  if row == range[3] then
    return col <= range[4] + slack_cols
  end
  return true
end

local function should_preserve_preview(bufnr, cursor_row, cursor_col)
  local mode = vim.api.nvim_get_mode().mode or ""
  if not is_insert_like_mode(mode) then
    return false
  end

  local bs = state.get_buf_state(bufnr)
  return bs.preview_image ~= nil and cursor_near_range(bs.preview_source_range, cursor_row, cursor_col)
end

local function stable_preview_to_keep(bs)
  if bs == nil or bs.preview_image == nil then
    return nil, false
  end
  if item_has_stable_render(bs.preview_item) and bs.preview_image.image_id == bs.preview_item.image_id then
    return bs.preview_item, true
  end
  if
    item_has_stable_render(bs.preview_last_rendered_item)
    and bs.preview_image.image_id == bs.preview_last_rendered_item.image_id
  then
    return bs.preview_last_rendered_item, false
  end
  return nil, false
end

local function preview_left_pad_cols(bufnr, range)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    local line = (vim.api.nvim_buf_get_lines(bufnr, range[1], range[1] + 1, false) or { "" })[1] or ""
    local prefix = string.sub(line, 1, range[2])
    return vim.fn.strdisplaywidth(prefix)
  end

  local sp = vim.fn.screenpos(winid, range[1] + 1, range[2] + 1)
  local winpos = vim.api.nvim_win_get_position(winid)
  local textoff = vim.fn.getwininfo(winid)[1].textoff or 0
  local screen_col = math.max(1, (sp.col or 1) - winpos[2] - textoff)
  return screen_col - 1
end

local function get_range_screen_rect(bufnr, range)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end

  local start_sp = vim.fn.screenpos(winid, range[1] + 1, range[2] + 1)
  local end_col = math.max(range[2] + 1, range[4])
  local end_sp = vim.fn.screenpos(winid, range[3] + 1, end_col)
  if start_sp == nil or end_sp == nil then
    return nil
  end

  return {
    winid = winid,
    top = math.max(0, (start_sp.row or 1) - 1),
    bottom = math.max(0, (end_sp.row or 1) - 1),
    left = math.max(0, (start_sp.col or 1) - 1),
  }
end

local function make_preview_screen_rect(anchor_rect, natural_cols, natural_rows, vertical)
  local top
  if vertical == "above" then
    top = anchor_rect.top - natural_rows
  else
    top = anchor_rect.bottom + 1
  end
  return {
    top = top,
    bottom = top + natural_rows - 1,
    left = anchor_rect.left,
    right = anchor_rect.left + natural_cols - 1,
    width = natural_cols,
    height = natural_rows,
    vertical = vertical,
  }
end

local function choose_preview_vertical(bufnr, range, natural_cols, natural_rows)
  local bs = state.get_buf_state(bufnr)
  local preferred = (bs.preview_float and bs.preview_float.vertical) or "above"
  local anchor_rect = get_range_screen_rect(bufnr, range)
  if anchor_rect == nil then
    return preferred
  end

  local obstacles = list_nearby_float_obstacles(nil, {
    row = anchor_rect.top,
    col = anchor_rect.left,
  })
  local editor_h = vim.o.lines - vim.o.cmdheight
  local editor_w = vim.o.columns

  local preferred_rect = make_preview_screen_rect(anchor_rect, natural_cols, natural_rows, preferred)
  preferred_rect.bounds_penalty = candidate_bounds_penalty(preferred_rect, editor_h, editor_w)
  preferred_rect.obstacle_penalty = candidate_obstacle_penalty(preferred_rect, obstacles)
  if preferred_rect.bounds_penalty == 0 and preferred_rect.obstacle_penalty == 0 then
    return preferred
  end

  local alternate = preferred == "above" and "below" or "above"
  local alternate_rect = make_preview_screen_rect(anchor_rect, natural_cols, natural_rows, alternate)
  alternate_rect.bounds_penalty = candidate_bounds_penalty(alternate_rect, editor_h, editor_w)
  alternate_rect.obstacle_penalty = candidate_obstacle_penalty(alternate_rect, obstacles)
  local preferred_penalty = preferred_rect.bounds_penalty + preferred_rect.obstacle_penalty
  local alternate_penalty = alternate_rect.bounds_penalty + alternate_rect.obstacle_penalty
  if alternate_penalty < preferred_penalty then
    bs.preview_float.vertical = alternate
    return alternate
  end

  return preferred
end

--- Full reset of all concealer state for a buffer (called on disable or wipeout).
--- @param bufnr integer
function M.hard_reset_buf(bufnr)
  state.clear_hover_timer(bufnr)
  state.clear_visible_refresh_timer(bufnr)
  state.clear_preview_timer(bufnr)
  require("math-conceal.image.apply").hard_reset(bufnr)
  require("math-conceal.image.machine.runtime").reset_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id2, 0, -1)
  state.buffers[bufnr] = nil
  diagnostics = {}
end

--- Re-render all Typst nodes in bufnr.
--- @param bufnr integer|nil  defaults to current buffer
function M.render_buf(bufnr)
  local main = require("math-conceal.image")
  bufnr = bufnr or vim.fn.bufnr()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  clear_diagnostics(bufnr)
  require("math-conceal.image.machine.runtime").reconcile_visible_overlay_bindings(bufnr)

  if main._enabled_buffers[bufnr] ~= true or not main.is_render_allowed(bufnr) then
    M.hard_reset_buf(bufnr)
    require("math-conceal.image.session").stop_compiler_service(bufnr)
    return
  end

  diagnostics = {}
  local scan, scan_reason = scan_formula_matches(bufnr, main)
  if scan_reason == "unsupported" then
    M.hard_reset_buf(bufnr)
    return
  end
  if scan == nil then
    return
  end

  state.buffer_render_state[bufnr] = state.buffer_render_state[bufnr] or {}
  state.buffer_render_state[bufnr].full_units = scan.units
  state.buffer_render_state[bufnr].runtime_preludes = scan.runtime_preludes
  state.buffer_render_state[bufnr].render_viewport = scan.render_viewport
  state.buffer_render_state[bufnr].render_viewport_key = scan.render_viewport_key
  state.buffer_render_state[bufnr].render_coverage = scan.render_coverage
  state.buffer_render_state[bufnr].render_coverage_key = scan.render_coverage_key
  state.buffer_render_state[bufnr].render_coverage_state = scan.render_coverage_state
  state.buffer_render_state[bufnr].render_coverage_complete = scan.render_coverage_complete

  local runtime = require("math-conceal.image.machine.runtime")
  local project_scope = require("math-conceal.image.project-scope").resolve(bufnr, "full")
  local scan_event = {
    type = "nodes_scanned",
    bufnr = bufnr,
    project_scope_id = project_scope.project_scope_id,
    render_context_hash = full_render_context_hash(main, project_scope),
    buffer_version = vim.api.nvim_buf_get_changedtick(bufnr),
    layout_version = vim.o.columns,
    scanned_nodes = scan.scanned_nodes,
    binding_dirty_ranges = scan.binding_dirty_ranges,
    render_viewport = scan.render_viewport,
    render_viewport_key = scan.render_viewport_key,
    render_coverage = scan.render_coverage,
    render_coverage_key = scan.render_coverage_key,
  }
  if uses_formula_manager(bufnr, main, project_scope) then
    require("math-conceal.image.formula.manager").update_from_scan(scan_event)
  else
    runtime.dispatch(scan_event)
    runtime.dispatch({
      type = "full_render_requested",
      bufnr = bufnr,
    })
  end

  -- Reset hover guard so hide_extmarks_at_cursor re-evaluates after render
  runtime.invalidate_hover(bufnr)
  M.hide_extmarks_at_cursor(bufnr)

  if scan.render_coverage_can_grow then
    M.schedule_full_render(bufnr, { delay_ms = scan.render_coverage_delay_ms })
  end
  M.sync_progressive_render(bufnr)
end

local function active_progressive_typst_parent_key(bufnr)
  if buffer_source_kind(bufnr) ~= "typst" then
    return nil
  end

  local ok_main, main = pcall(require, "math-conceal.image")
  if not ok_main or main._enabled_buffers[bufnr] ~= true or not main.is_render_allowed(bufnr) then
    return nil
  end

  local mode = vim.api.nvim_get_mode().mode or ""
  if main.config.conceal_in_normal and mode:find("n", 1, true) ~= nil then
    return nil
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if not ok_cursor or cursor == nil then
    return nil
  end

  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local brs = state.buffer_render_state[bufnr]
  local units = brs and brs.full_units or nil
  for _, unit in ipairs(units or {}) do
    if unit.node_type == "code" then
      local item = {
        bufnr = bufnr,
        range = unit.range,
        node_type = "code",
        semantics = { source_kind = "code" },
      }
      if cursor_visibility.should_unconceal_item_for_row(item, cursor_row, cursor_row, cursor_col, mode) then
        return typst_unit_key(unit)
      end
    end
  end

  return nil
end

function M.sync_progressive_render(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local bs = state.get_buf_state(bufnr)
  local next_key = active_progressive_typst_parent_key(bufnr)
  if bs.progressive_typst_parent_key == next_key then
    return
  end

  bs.progressive_typst_parent_key = next_key
  M.schedule_full_render(bufnr, { immediate = true })
end

--- Hide a single extmark (removes virt_text/virt_lines from display).
--- Returns true when the extmark was hidden and should be tracked.
--- @param bufnr integer
--- @param bs table  per-buffer state
--- @param extmark_id integer
--- @param opts table|nil
local function hide_one_extmark(bufnr, _bs, extmark_id, opts)
  return require("math-conceal.image.extmark").unconceal_extmark(bufnr, extmark_id, opts)
end

--- Restore a previously hidden extmark from the current rendered item state.
--- @param bufnr integer
--- @param extmark_id integer
--- @param opts table|nil
local function restore_one_extmark(bufnr, extmark_id, opts)
  local bs = state.get_buf_state(bufnr)
  local brs = state.buffer_render_state[bufnr]
  if brs == nil or brs.extmark_to_item == nil then
    return
  end
  local item = brs.extmark_to_item[extmark_id]
  if item == nil or item.natural_cols == nil or item.natural_rows == nil then
    return
  end
  local effective_range = get_item_effective_range(item)
  if effective_range == nil then
    return
  end
  bs.currently_hidden_extmark_ids[extmark_id] = nil
  local extmark = require("math-conceal.image.extmark")
  extmark.conceal_for_image_id(
    bufnr,
    item.image_id,
    item.natural_cols,
    item.natural_rows,
    item.source_rows or (effective_range[3] - effective_range[1] + 1),
    opts
  )
end

local function should_unconceal_item_for_row(item, row, cursor_row, cursor_col, mode)
  return cursor_visibility.should_unconceal_item_for_row(item, row, cursor_row, cursor_col, mode)
end

--- Hide / restore extmarks that overlap the cursor position.
--- Called on CursorMoved and ModeChanged.
--- @param bufnr integer
function M.hide_extmarks_at_cursor(bufnr)
  local main = require("math-conceal.image")
  if uses_formula_manager(bufnr, main) then
    require("math-conceal.image.formula.manager").sync_cursor_conceal(bufnr)
    return
  end

  local bs = state.get_buf_state(bufnr)
  local hover = require("math-conceal.image.machine.runtime").get_ui_buffer(bufnr).hover

  if main._enabled_buffers[bufnr] ~= true or not main.is_render_allowed(bufnr) then
    for id in pairs(bs.currently_hidden_extmark_ids) do
      restore_one_extmark(bufnr, id)
    end
    bs.currently_hidden_extmark_ids = {}
    hover.last_cursor_row = nil
    hover.last_cursor_col = nil
    hover.last_mode = nil
    hover.last_lo = nil
    hover.last_hi = nil
    hover.invalidated = false
    return
  end

  local mode = vim.api.nvim_get_mode().mode

  -- conceal_in_normal mode: don't hide anything, restore all hidden extmarks
  if main.config.conceal_in_normal and mode:find("n", 1, true) ~= nil then
    for id in pairs(bs.currently_hidden_extmark_ids) do
      restore_one_extmark(bufnr, id)
    end
    bs.currently_hidden_extmark_ids = {}
    hover.last_cursor_row = nil -- force re-process on next call
    hover.last_cursor_col = nil
    hover.last_mode = mode
    hover.last_lo = nil
    hover.last_hi = nil
    hover.invalidated = false
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]

  -- Determine row range to unconceal
  local is_visual = mode == "v" or mode == "V" or mode == "\22"
  local lo, hi = cursor_row, cursor_row
  if is_visual then
    local vrow = vim.fn.getpos("v")[2] - 1
    lo, hi = math.min(cursor_row, vrow), math.max(cursor_row, vrow)
  end

  -- Skip only when the cursor span is unchanged and no render pass has
  -- invalidated the current hide/restore decision.
  if
    hover.last_mode == mode
    and hover.last_lo == lo
    and hover.last_hi == hi
    and hover.last_cursor_col == cursor_col
    and not hover.invalidated
  then
    return
  end

  -- Collect items to hide from line index (no nvim_buf_get_extmarks call)
  local brs = state.buffer_render_state[bufnr]
  local line_to_items = (brs and brs.line_to_items) or {}
  local should_hide = {} -- extmark_id -> item
  for row = lo, hi do
    local row_items = line_to_items[row]
    if row_items then
      for _, item in ipairs(row_items) do
        if should_unconceal_item_for_row(item, row, cursor_row, cursor_col, mode) then
          should_hide[item.extmark_id] = item
        end
      end
    end
  end

  -- Differential update
  local new_hidden = {}

  -- Restore extmarks no longer under cursor
  for extmark_id in pairs(bs.currently_hidden_extmark_ids) do
    if should_hide[extmark_id] then
      new_hidden[extmark_id] = true -- still under cursor, keep hidden
    else
      restore_one_extmark(bufnr, extmark_id, { defer_line_run_reconcile = true })
    end
  end

  -- Hide newly entered extmarks
  for extmark_id, _ in pairs(should_hide) do
    if not bs.currently_hidden_extmark_ids[extmark_id] then
      local hidden = hide_one_extmark(bufnr, bs, extmark_id, { defer_line_run_reconcile = true })
      if hidden ~= nil then
        new_hidden[extmark_id] = true
      end
    end
  end

  bs.currently_hidden_extmark_ids = new_hidden
  require("math-conceal.image.extmark").reconcile_cursor_line_runs(bufnr, lo, hi)
  hover.last_cursor_row = cursor_row
  hover.last_cursor_col = cursor_col
  hover.last_mode = mode
  hover.last_lo = lo
  hover.last_hi = hi
  hover.invalidated = false
end

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function rect_intersection_area(a, b)
  local left = math.max(a.left, b.left)
  local right = math.min(a.right, b.right)
  local top = math.max(a.top, b.top)
  local bottom = math.min(a.bottom, b.bottom)
  if left > right or top > bottom then
    return 0
  end
  return (right - left + 1) * (bottom - top + 1)
end

local function get_cursor_anchor_screenpos(bufnr)
  local src_winid = vim.fn.bufwinid(bufnr)
  if src_winid == -1 then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(src_winid)
  local sp = vim.fn.screenpos(src_winid, cursor[1], cursor[2] + 1)

  -- screenpos() returns 1-based screen coordinates; float config uses editor-relative row/col.
  local row = math.max(0, (sp.row or 1) - 1)
  local col = math.max(0, (sp.col or 1) - 1)

  return {
    src_winid = src_winid,
    row = row,
    col = col,
  }
end

local function get_float_rect(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  local cfg = vim.api.nvim_win_get_config(winid)
  if cfg.relative == nil or cfg.relative == "" then
    return nil
  end

  local pos = vim.api.nvim_win_get_position(winid)
  local height = vim.api.nvim_win_get_height(winid)
  local width = vim.api.nvim_win_get_width(winid)

  local top = pos[1]
  local left = pos[2]

  return {
    winid = winid,
    top = top,
    left = left,
    bottom = top + height - 1,
    right = left + width - 1,
    width = width,
    height = height,
    zindex = cfg.zindex or 50,
    focusable = cfg.focusable ~= false,
  }
end

local function is_near_anchor(rect, anchor)
  -- only cares about floats that are roughly in the same area as the cursor, to reduce the number of obstacles and speed up scoring
  local margin_row = 12
  local margin_col = 50
  return not (
    rect.bottom < anchor.row - margin_row
    or rect.top > anchor.row + margin_row
    or rect.right < anchor.col - margin_col
    or rect.left > anchor.col + margin_col
  )
end

list_nearby_float_obstacles = function(exclude_winid, anchor)
  local ret = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if winid ~= exclude_winid then
      local rect = get_float_rect(winid)
      if rect ~= nil and is_near_anchor(rect, anchor) then
        ret[#ret + 1] = rect
      end
    end
  end
  return ret
end

local function make_candidate_rect(anchor, width, height, row, col, vertical)
  return {
    top = row,
    left = col,
    bottom = row + height - 1,
    right = col + width - 1,
    width = width,
    height = height,
    dist = math.abs(row - anchor.row) + math.abs(col - anchor.col),
    vertical = vertical,
  }
end

candidate_bounds_penalty = function(rect, editor_h, editor_w)
  local penalty = 0

  if rect.top < 0 then
    penalty = penalty + 1000 + -rect.top * 20
  end
  if rect.left < 0 then
    penalty = penalty + 1000 + -rect.left * 20
  end
  if rect.bottom >= editor_h then
    penalty = penalty + 1000 + (rect.bottom - editor_h + 1) * 20
  end
  if rect.right >= editor_w then
    penalty = penalty + 1000 + (rect.right - editor_w + 1) * 20
  end

  return penalty
end

candidate_obstacle_penalty = function(rect, obstacles)
  local penalty = 0

  for _, obs in ipairs(obstacles) do
    local area = rect_intersection_area(rect, obs)
    if area > 0 then
      local weight = (obs.zindex >= 100) and 8 or 4
      penalty = penalty + area * weight
    end
  end

  return penalty
end

scan_formula_matches = function(bufnr, main)
  state.runtime_preludes = {}

  local bs = state.get_buf_state(bufnr)
  local prev_state = state.buffer_render_state[bufnr] or {}
  local source_kind = buffer_source_kind(bufnr)
  if source_kind ~= "typst" and source_kind ~= "markdown" and source_kind ~= "latex" then
    return nil, "unsupported"
  end
  local viewport_mod = require("math-conceal.image.viewport")
  local render_plan = viewport_mod.resolve_render_plan(bufnr, { source_kind = source_kind })

  local units
  local sorted_entries = {}
  local binding_dirty_ranges = bs.binding_dirty_ranges

  if source_kind == "typst" then
    local parser, parser_err = get_buffer_parser(bufnr, "typst")
    if parser == nil then
      schedule_parser_retry(bufnr, "typst", bs, parser_err)
      return nil, "parser"
    end
    if bs.parser_retry_counts then
      bs.parser_retry_counts.typst = nil
    end
    local tree = parser:parse()[1]:root()
    units = collect_incremental_units(bufnr, tree, main._typst_query, prev_state.full_units, bs.pending_change)
    if units == nil then
      units = collect_full_units(bufnr, tree, main._typst_query)
    end
    sorted_entries = build_render_entries_from_units(bufnr, units, {
      progressive_parent_key = bs.progressive_typst_parent_key,
      query = main._typst_query,
    })
  elseif source_kind == "markdown" then
    units = require("math-conceal.image.source-adapters.markdown").collect(bufnr)
    sorted_entries = units
  else
    local parser, parser_err = get_buffer_parser(bufnr, "latex")
    if parser == nil then
      schedule_parser_retry(bufnr, "latex", bs, parser_err)
      return nil, "parser"
    end
    if bs.parser_retry_counts then
      bs.parser_retry_counts.latex = nil
    end
    sorted_entries, units = require("math-conceal.image.source-adapters.latex").collect(bufnr, {
      parser = parser,
      prev_units = prev_state.full_units,
      pending_change = bs.pending_change,
    })
  end

  bs.pending_change = nil
  bs.binding_dirty_ranges = nil

  local scanned_nodes = {}
  for idx, entry in ipairs(sorted_entries) do
    local range, prelude_count, node_type = entry.range, entry.prelude_count, entry.node_type
    local sem = entry.semantics or semantics_mod.classify(range, bufnr, node_type)
    local source_str = entry.source_text or range_to_string(range, bufnr)
    local str = entry.render_text or source_str
    local display_range = entry.display_range or range
    local display_prefix = nil
    local display_suffix = nil

    if entry.display_range == nil and node_type == "math" and sem.display_kind == "block" and range[1] == range[3] then
      display_range = full_line_range(bufnr, range[1])

      if sem.render_whole_line then
        local line = line_text(bufnr, range[1])
        display_prefix = trim_right(line:sub(1, range[2]))
        display_suffix = trim_left(line:sub(range[4] + 1))
      end
    end

    scanned_nodes[#scanned_nodes + 1] = {
      item_idx = idx,
      stable_key = entry.stable_key or (entry.ts_node and tostring(entry.ts_node:id()) or nil),
      source_range = range,
      display_range = display_range,
      display_prefix = display_prefix,
      display_suffix = display_suffix,
      source_text = str,
      source_str = source_str,
      source_text_hash = hash_string(str),
      context_hash = context_hash(prelude_count),
      prelude_count = prelude_count,
      node_type = node_type,
      backend_node_type = entry.backend_node_type,
      semantics = sem,
      requires_mitex = entry.requires_mitex == true,
      render_in_coverage = viewport_mod.range_overlaps(render_plan.render_coverage, display_range),
      render_priority = viewport_mod.distance_to_viewport(render_plan.render_viewport, display_range),
    }
  end

  return {
    units = units,
    scanned_nodes = scanned_nodes,
    binding_dirty_ranges = binding_dirty_ranges,
    runtime_preludes = state.runtime_preludes,
    render_viewport = render_plan.render_viewport,
    render_viewport_key = render_plan.render_viewport_key,
    render_coverage = render_plan.render_coverage,
    render_coverage_key = render_plan.render_coverage_key,
    render_coverage_state = render_plan.render_coverage_state,
    render_coverage_complete = render_plan.render_coverage_complete,
    render_coverage_can_grow = render_plan.render_coverage_can_grow,
    render_coverage_delay_ms = render_plan.render_coverage_delay_ms,
  }
end

function M.scan_formula_matches(bufnr)
  return scan_formula_matches(bufnr, require("math-conceal.image"))
end

local function candidate_penalty(rect, obstacles, editor_h, editor_w)
  local bounds_penalty = candidate_bounds_penalty(rect, editor_h, editor_w)
  local obstacle_penalty = candidate_obstacle_penalty(rect, obstacles)
  rect.bounds_penalty = bounds_penalty
  rect.obstacle_penalty = obstacle_penalty
  return bounds_penalty + obstacle_penalty + rect.dist
end

local function choose_preview_rect(bufnr, width, height, exclude_winid)
  local anchor = get_cursor_anchor_screenpos(bufnr)
  if anchor == nil then
    return nil
  end
  local bs = state.get_buf_state(bufnr)
  local obstacles = list_nearby_float_obstacles(exclude_winid, anchor)

  local editor_h = vim.o.lines - vim.o.cmdheight
  local editor_w = vim.o.columns
  local preferred_vertical = (bs.preview_float and bs.preview_float.vertical) or "above"

  local candidates = {
    make_candidate_rect(anchor, width, height, anchor.row - height, anchor.col + 1, "above"),
    make_candidate_rect(anchor, width, height, anchor.row - height, anchor.col - width - 1, "above"),
    make_candidate_rect(anchor, width, height, anchor.row - height - 1, anchor.col, "above"),
    make_candidate_rect(anchor, width, height, anchor.row + 1, anchor.col + 1, "below"),
    make_candidate_rect(anchor, width, height, anchor.row + 1, anchor.col - width - 1, "below"),
    make_candidate_rect(anchor, width, height, anchor.row + 2, anchor.col, "below"),
    make_candidate_rect(anchor, width, height, anchor.row, anchor.col + 2, preferred_vertical),
    make_candidate_rect(anchor, width, height, anchor.row, anchor.col - width - 2, preferred_vertical),
  }

  local best = nil
  local best_penalty = math.huge
  local preferred_best = nil
  local preferred_best_penalty = math.huge

  for _, rect in ipairs(candidates) do
    local p = candidate_penalty(rect, obstacles, editor_h, editor_w)
    if
      rect.vertical == preferred_vertical
      and rect.bounds_penalty == 0
      and rect.obstacle_penalty == 0
      and p < preferred_best_penalty
    then
      preferred_best = rect
      preferred_best_penalty = p
    end
    if p < best_penalty then
      best = rect
      best_penalty = p
    end
  end

  best = preferred_best or best
  best.top = clamp(best.top, 0, math.max(0, editor_h - height))
  best.left = clamp(best.left, 0, math.max(0, editor_w - width))

  return best
end

local function preview_win_config(bufnr, width, height, for_create)
  local bs = state.get_buf_state(bufnr)
  local preview_winid = bs.preview_float and bs.preview_float.winid or nil
  local rect = choose_preview_rect(bufnr, math.max(1, width or 1), math.max(1, height or 1), preview_winid)
  if rect == nil then
    return nil
  end
  if bs.preview_float ~= nil and rect.bounds_penalty == 0 and rect.obstacle_penalty == 0 then
    bs.preview_float.vertical = rect.vertical or bs.preview_float.vertical or "above"
  end

  local config = {
    relative = "editor",
    row = rect.top,
    col = rect.left,
    width = rect.width,
    height = rect.height,
    style = "minimal",
    focusable = false,
    zindex = 250,
  }
  if for_create then
    config.noautocmd = true
  end
  return config
end

local function ensure_live_preview_float(bufnr)
  local bs = state.get_buf_state(bufnr)
  local pf = bs.preview_float

  if pf.bufnr == nil or not vim.api.nvim_buf_is_valid(pf.bufnr) then
    pf.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[pf.bufnr].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(pf.bufnr, 0, -1, false, { "", "" })
  end

  if vim.api.nvim_buf_line_count(pf.bufnr) < PREVIEW_FLOAT_LINE_COUNT then
    vim.api.nvim_buf_set_lines(pf.bufnr, 0, -1, false, { "", "" })
  end

  if pf.winid == nil or not vim.api.nvim_win_is_valid(pf.winid) then
    local cfg = preview_win_config(bufnr, pf.width, pf.height, true)
    if cfg == nil then
      close_live_preview_float(bufnr)
      return nil
    end
    pf.winid = vim.api.nvim_open_win(pf.bufnr, false, cfg)
  else
    local cfg = preview_win_config(bufnr, pf.width, pf.height, false)
    if cfg == nil then
      close_live_preview_float(bufnr)
      return nil
    end
    vim.api.nvim_win_set_config(pf.winid, cfg)
  end

  return pf
end

local function ensure_preview_float_lines(bufnr, line_count)
  local bs = state.get_buf_state(bufnr)
  local pf = bs.preview_float
  if pf.bufnr == nil or not vim.api.nvim_buf_is_valid(pf.bufnr) then
    return
  end

  local count = math.max(PREVIEW_FLOAT_LINE_COUNT, line_count or 1)
  local lines = {}
  for _ = 1, count do
    lines[#lines + 1] = ""
  end
  vim.api.nvim_buf_set_lines(pf.bufnr, 0, -1, false, lines)
end

local function close_live_preview_float(bufnr)
  local bs = state.get_buf_state(bufnr)
  local pf = bs.preview_float

  if pf.winid ~= nil and vim.api.nvim_win_is_valid(pf.winid) then
    pcall(vim.api.nvim_win_close, pf.winid, true)
  end
  if pf.bufnr ~= nil and vim.api.nvim_buf_is_valid(pf.bufnr) then
    pcall(vim.api.nvim_buf_delete, pf.bufnr, { force = true })
  end

  bs.preview_float = {
    bufnr = nil,
    winid = nil,
    width = 1,
    height = 1,
    vertical = "above",
  }
end

function M.sync_live_preview_float(bufnr, width, height)
  local pf = ensure_live_preview_float(bufnr)
  if pf == nil then
    return
  end
  if width ~= nil then
    pf.width = math.max(1, width)
  end
  if height ~= nil then
    pf.height = math.max(1, height)
  end
  if pf.winid ~= nil and vim.api.nvim_win_is_valid(pf.winid) then
    vim.api.nvim_win_set_config(pf.winid, preview_win_config(bufnr, pf.width, pf.height, false))
  end
end

local function find_full_item_at_cursor(bufnr, row, col, mode)
  local bstate = state.buffer_render_state[bufnr]
  if bstate == nil or bstate.full_items == nil then
    return nil
  end

  local candidates = bstate.line_to_items and bstate.line_to_items[row] or bstate.full_items
  local best_item = nil
  for _, item in ipairs(candidates) do
    local effective_range = get_item_effective_range(item)
    if
      effective_range ~= nil
      and item.node_type == "math"
      and cursor_engages_inline_item(effective_range, row, col, mode)
    then
      if best_item == nil then
        best_item = item
      else
        local best_range = get_item_effective_range(best_item)
        local best_span = (best_range[3] - best_range[1]) * 100000 + (best_range[4] - best_range[2])
        local item_span = (effective_range[3] - effective_range[1]) * 100000 + (effective_range[4] - effective_range[2])
        if item_span > best_span then
          best_item = item
        end
      end
    end
  end

  return best_item
end

local present_preview_item

function M.render_live_typst_preview_for_item(bufnr, item, cursor_row, cursor_col, mode)
  if item == nil then
    return false
  end

  local preview_str, render_key, source_str = make_highlighted_preview_math(item, cursor_row, cursor_col, mode)
  if type(preview_str) ~= "string" or type(render_key) ~= "string" or type(source_str) ~= "string" then
    M.clear_live_typst_preview(bufnr)
    return false
  end
  local bs = state.get_buf_state(bufnr)
  local preview = require("math-conceal.image.machine.runtime").get_ui_buffer(bufnr).preview
  if bs.preview_item ~= nil and preview.render_key == render_key and item_has_stable_render(bs.preview_item) then
    M.present_rendered_preview_item(bufnr, bs.preview_item)
    return true, bs.preview_item, render_key
  end
  if preview.render_key == render_key then
    local previous_stable_preview = stable_preview_to_keep(bs)
    if previous_stable_preview ~= nil then
      return true, previous_stable_preview, render_key
    end
    present_preview_item(bufnr, item, cursor_row, cursor_col)
    return true, item, render_key
  end

  local previous_preview_item = bs.preview_item
  local previous_stable_preview, previous_stable_is_active = stable_preview_to_keep(bs)
  if previous_stable_preview ~= nil then
    bs.preview_last_rendered_item = previous_stable_preview
  end
  if previous_stable_is_active then
    bs.preview_last_render_key = preview.render_key
    preview.last_render_key = preview.render_key
  end
  if previous_stable_preview == nil then
    present_preview_item(bufnr, item, cursor_row, cursor_col)
  end

  local shared_extmark_id = bs.preview_image and bs.preview_image.extmark_id or nil
  if
    previous_preview_item ~= nil
    and previous_preview_item ~= previous_stable_preview
    and (bs.preview_image == nil or previous_preview_item.image_id ~= bs.preview_image.image_id)
  then
    cleanup_preview_item_request(bufnr, previous_preview_item, { keep_extmark = shared_extmark_id ~= nil })
  end

  local preview_item = require("math-conceal.image.apply").allocate_preview_item(
    bufnr,
    item,
    preview_str,
    source_str,
    render_key,
    shared_extmark_id
  )
  require("math-conceal.image.machine.runtime").render_preview_tail(bufnr, preview_item)
  return true, preview_item, render_key
end

present_preview_item = function(bufnr, item, cursor_row, cursor_col)
  if item == nil then
    cleanup_preview_image(bufnr)
    return
  end

  local bs = state.get_buf_state(bufnr)
  local effective_range = get_item_effective_range(item)
  if effective_range == nil then
    cleanup_preview_image(bufnr)
    return
  end
  if not item_has_stable_render(item) then
    if bs.preview_source_image_id == item.image_id and bs.preview_image ~= nil then
      return
    end
    if item_has_stable_render(bs.preview_last_rendered_item) then
      M.present_rendered_preview_item(bufnr, bs.preview_last_rendered_item)
      return
    end
    if should_preserve_preview(bufnr, cursor_row, cursor_col) then
      return
    end
    cleanup_preview_image(bufnr)
    return
  end

  local vertical = choose_preview_vertical(bufnr, effective_range, item.natural_cols, item.natural_rows)
  require("math-conceal.image.apply").show_preview_item(bufnr, item, {
    vertical = vertical,
    anchor_row = vertical == "above" and effective_range[1] or effective_range[3],
    left_pad_cols = preview_left_pad_cols(bufnr, effective_range),
    effective_range = effective_range,
  })
end

function M.present_rendered_preview_item(bufnr, item)
  if item == nil then
    cleanup_preview_image(bufnr)
    return
  end

  local effective_range = get_item_effective_range(item)
  if effective_range == nil then
    cleanup_preview_image(bufnr)
    return
  end
  if not item_has_stable_render(item) then
    return
  end

  local vertical = choose_preview_vertical(bufnr, effective_range, item.natural_cols, item.natural_rows)
  require("math-conceal.image.apply").show_rendered_preview_item(bufnr, item, {
    vertical = vertical,
    anchor_row = vertical == "above" and effective_range[1] or effective_range[3],
    left_pad_cols = preview_left_pad_cols(bufnr, effective_range),
    effective_range = effective_range,
  })
end

--- Stop the live preview tail page and remove its extmark/image.
--- @param bufnr integer
--- @param opts table|nil
function M.clear_live_typst_preview(bufnr, opts)
  require("math-conceal.image.machine.runtime").clear_preview_request(bufnr)
  cleanup_preview_image(bufnr, opts)
end

--- Coalesce insert-mode text/cursor churn into a single preview sync pipeline.
--- @param bufnr integer
--- @param opts table|nil { refresh_full?: boolean, immediate?: boolean }
function M.schedule_full_render(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  if bs._full_render_timer == nil or bs._full_render_timer:is_closing() then
    bs._full_render_timer = vim.uv.new_timer()
  end

  bs._full_render_timer:stop()
  bs._full_render_timer:start(
    opts.immediate == true and 0 or (opts.delay_ms or 16),
    0,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      M.render_buf(bufnr)
      M.hide_extmarks_at_cursor(bufnr)
    end)
  )
end

function M.schedule_live_preview_sync(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {}
  local main = require("math-conceal.image")
  local bs = state.get_buf_state(bufnr)
  local preview = require("math-conceal.image.machine.runtime").get_ui_buffer(bufnr).preview
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  preview.sync_tick = tick

  -- When text changes in insert mode (refresh_full=true), fire the full
  -- render on a very short debounce (1 frame ≈ 16ms) so that overlays
  -- update almost immediately.  The heavier live-preview float keeps the
  -- longer user-configured debounce to avoid flicker.
  if opts.refresh_full == true then
    M.schedule_full_render(bufnr)
  end

  if bs.preview_sync_timer == nil or bs.preview_sync_timer:is_closing() then
    bs.preview_sync_timer = vim.uv.new_timer()
  end

  local delay = opts.immediate == true and 0 or (main.config.live_preview_debounce or 100)
  bs.preview_sync_timer:stop()
  bs.preview_sync_timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      local current_preview = require("math-conceal.image.machine.runtime").get_ui_buffer(bufnr).preview

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Full render already dispatched above; only re-render if a further
      -- tick change happened between the fast timer and this slower one.
      local scheduled_tick = current_preview.sync_tick
      current_preview.sync_tick = nil
      if scheduled_tick ~= nil and scheduled_tick ~= vim.api.nvim_buf_get_changedtick(bufnr) then
        M.render_buf(bufnr)
      end
      require("math-conceal.image.machine.runtime").render_live_preview(bufnr)
      M.hide_extmarks_at_cursor(bufnr)
    end)
  )
end

--- Render a live preview image in virtual lines around the math node under the cursor.
--- @param bufnr integer
function M.render_live_typst_preview(bufnr)
  local main = require("math-conceal.image")
  if
    main._enabled_buffers[bufnr] ~= true
    or not main.is_render_allowed(bufnr)
    or (main.config and main.config.live_preview_enabled == false)
  then
    M.clear_live_typst_preview(bufnr)
    return
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    M.clear_live_typst_preview(bufnr)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local mode = vim.api.nvim_get_mode().mode or ""

  -- Live preview must target the same maximal math units as full rendering.
  -- Reusing the full-item index avoids previewing nested descendants that are
  -- not independently rendered, which could otherwise duplicate the formula
  -- under the cursor while anchoring the float to the wrong range.
  local item = find_full_item_at_cursor(bufnr, cursor_row, cursor_col, mode)
  if item ~= nil then
    M.render_live_typst_preview_for_item(bufnr, item, cursor_row, cursor_col, mode)
    return
  end

  if should_preserve_preview(bufnr, cursor_row, cursor_col) then
    return
  end
  M.clear_live_typst_preview(bufnr)
end

-- Register post-render UI reaction hooks so apply.lua can trigger them
-- without a direct reverse require("math-conceal.image.plan") dependency.
state.hooks.on_page_committed = function(bufnr)
  local runtime = require("math-conceal.image.machine.runtime")
  runtime.sync_hover(bufnr)
  runtime.render_live_preview(bufnr)
end
state.hooks.present_rendered_preview_item = function(bufnr, item)
  M.present_rendered_preview_item(bufnr, item)
end

return M
