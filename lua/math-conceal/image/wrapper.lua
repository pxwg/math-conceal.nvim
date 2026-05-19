--- Typst document wrapper construction for math-conceal.image.
--- Builds the Typst source that wraps each snippet so it renders at the correct
--- cell-grid dimensions.
---
--- Typst document assembly interface
---   M.build_batch_document(items) -> string    assembled multi-page Typst source
---   M.build_item_fragment(item, ...)           assembled single-item fragment for inclusion
---   M.build_wrapper(item, source_rows)         per-item wrapper dispatch
---   M.make_inline_sizing_wrap(source_rows)     intrinsic-constraint wrapper
---   M.make_flow_block_wrap(bufnr)              flow-constraint wrapper
---                                              (page width = available cols, no terminal padding)
local state = require("math-conceal.image.state")
local M = {}

--- @param s string
--- @return integer
local function count_lines(s)
  if s == "" then
    return 0
  end
  local _, n = s:gsub("\n", "\n")
  if s:sub(-1) ~= "\n" then
    n = n + 1
  end
  return n
end

--- @param parts string[]
--- @param s string
--- @param cur_line integer
--- @return integer
local function push(parts, s, cur_line)
  parts[#parts + 1] = s
  return cur_line + count_lines(s)
end

--- Advance a 1-based (line, col) cursor through string s.
--- Column is also 1-based and points to the next character position.
--- @param s string
--- @param line integer
--- @param col integer
--- @return integer, integer
local function advance_pos(s, line, col)
  if s == "" then
    return line, col
  end

  local idx = 1
  while true do
    local nl = s:find("\n", idx, true)
    if nl == nil then
      return line, col + (#s - idx + 1)
    end
    line = line + 1
    col = 1
    idx = nl + 1
  end
end

--- @param item table
--- @return string
local function normalize_item_str(item)
  if type(item.str) == "table" then
    return table.concat(item.str)
  end
  if type(item.str) == "string" then
    return item.str
  end
  return ""
end

local function mitex_import_line()
  local config = require("math-conceal.image").config or {}
  local package = config.mitex_package or "@preview/mitex:0.2.7"
  if package == "" then
    return ""
  end
  return '#import "' .. package .. '": mitex, mi\n'
end

local function build_header_text(config, main, maybe_rewrite, preamble_include_line)
  local parts = {}
  if config.header and config.header ~= "" then
    parts[#parts + 1] = maybe_rewrite(config.header) .. "\n"
  end
  parts[#parts + 1] = main._styling_prelude
  if preamble_include_line ~= nil and preamble_include_line ~= "" then
    parts[#parts + 1] = preamble_include_line
  end
  return table.concat(parts)
end

--- Build document-level context text for service sidecar rendering.
--- @param bufnr integer
--- @param buf_dir string|nil
--- @param source_root string|nil
--- @param effective_root string|nil
--- @param preamble_include_line string|nil
--- @return string
function M.build_context_document(bufnr, buf_dir, source_root, effective_root, preamble_include_line)
  local main = require("math-conceal.image")
  local config = main.config
  local do_rewrite = buf_dir ~= nil and source_root ~= nil and effective_root ~= nil
  local pr = do_rewrite and require("math-conceal.image.path-rewrite") or nil
  local function maybe_rewrite(text)
    if pr == nil then
      return text
    end
    return pr.rewrite_paths(text, {
      bufnr = bufnr,
      buf_dir = buf_dir,
      source_root = source_root,
      effective_root = effective_root,
    })
  end
  return build_header_text(config, main, maybe_rewrite, preamble_include_line)
end

--- Returns the column width of the window displaying bufnr (falls back to current window).
--- @param bufnr integer
--- @return integer
local function get_win_cols(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  return vim.api.nvim_win_get_width(winid ~= -1 and winid or 0)
end

--- Returns available window width in Typst points.
--- Typst page width = 可用宽度（不含终端 padding）; terminal padding is added by extmark layer.
--- @param bufnr integer
--- @return number
local function current_window_width_pt(bufnr)
  local config = require("math-conceal.image").config
  local baseline_pt = config.math_baseline_pt or 11
  local pad_cols = config.block_padding_cols or 4
  local win_cols = get_win_cols(bufnr)
  local usable_cols = math.max(8, win_cols - 2 * pad_cols)
  if state._cell_px_w and state._cell_px_h then
    local cell_w_pt = baseline_pt * (state._cell_px_w / state._cell_px_h)
    return usable_cols * cell_w_pt
  end
  local approx_cell_w_pt = baseline_pt * 0.55
  return usable_cols * approx_cell_w_pt
end

--- Inline/intrinsic sizing wrapper.
--- Single-line items keep their measured width to avoid transparent right-side
--- padding; multi-line items still snap to the terminal cell grid.
--- @param source_rows integer
--- @return string prefix, string suffix   both "" when cell size is unknown
function M.make_inline_sizing_wrap(source_rows)
  local config = require("math-conceal.image").config
  if state._cell_px_h and state._cell_px_w then
    local baseline_pt = config.math_baseline_pt
    local cell_w_pt = baseline_pt * (state._cell_px_w / state._cell_px_h)
    if source_rows == 1 then
      return "#context { let __it = [",
        string.format(
          "]; let __d = measure(__it); let __mh = %gpt; let __mw = %gpt;"
            .. " let __rows = __d.height / __mh;"
            .. " if __rows <= 1.5 { block(width: __d.width, height: __mh, clip: true, align(horizon, __it)) }"
            .. " else { let __r = calc.max(1, calc.ceil(__rows - 0.001));"
            .. " block(width: __d.width, height: __r * __mh, align(horizon, __it)) } }\n",
          baseline_pt,
          cell_w_pt
        )
    else
      return "#context { let __it = [",
        string.format(
          "]; let __d = measure(__it); let __mh = %gpt; let __mw = %gpt;"
            .. " let __rows = calc.max(1, calc.ceil(__d.height / __mh - 0.001));"
            .. " let __cols = calc.max(1, calc.ceil(__d.width / __mw - 0.001));"
            .. " let __th = __rows * __mh; let __tw = __cols * __mw;"
            .. " block(width: __tw, height: __th, align(horizon, __it)) }\n",
          baseline_pt,
          cell_w_pt
        )
    end
  elseif state._cell_px_h then
    local baseline_pt = config.math_baseline_pt
    if source_rows == 1 then
      return "#context { let __it = [",
        string.format(
          "]; let __d = measure(__it); let __mh = %gpt;"
            .. " let __rows = __d.height / __mh;"
            .. " if __rows <= 1.5 { block(width: __d.width, height: __mh, clip: true, align(horizon, __it)) }"
            .. " else { let __r = calc.max(1, calc.ceil(__rows - 0.001));"
            .. " block(width: __d.width, height: __r * __mh, align(horizon, __it)) } }\n",
          baseline_pt
        )
    else
      return "#context { let __it = [",
        string.format(
          "]; let __d = measure(__it); let __mh = %gpt;"
            .. " let __rows = calc.max(1, calc.ceil(__d.height / __mh - 0.001));"
            .. " let __th = __rows * __mh;"
            .. " block(width: __d.width, height: __th, align(horizon, __it)) }\n",
          baseline_pt
        )
    end
  end
  return "", ""
end

--- Flow-block wrapper: Typst page width = available column width (no terminal padding).
--- Terminal display padding (block_padding_cols) is added separately in the extmark layer.
--- block_preview_margin_pt is Typst-side inset inside the rendered image (orthogonal to terminal padding).
--- @param bufnr integer
--- @return string prefix, string suffix
function M.make_flow_block_wrap(bufnr)
  local config = require("math-conceal.image").config
  local page_w_pt = current_window_width_pt(bufnr)
  local margin_pt = config.block_preview_margin_pt or 0
  return string.format(
    "#context {\n"
      .. "  set page(width: %gpt, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n"
      .. "  block(width: 100%%, inset: (x: %gpt, y: 0pt))[\n",
    page_w_pt,
    margin_pt
  ),
    "  ]\n}\n"
end

--- Wrapper dispatch: wrapper choice comes only from semantics.constraint_kind.
--- Missing semantics fall back to inline sizing for internal placeholders.
--- @param item table
--- @param source_rows integer
--- @return string prefix, string suffix
function M.build_wrapper(item, source_rows)
  if item.skip_wrapper == true then
    return "", ""
  end
  local semantics = item.semantics or {}
  if semantics.constraint_kind == "flow" then
    return M.make_flow_block_wrap(item.bufnr)
  else
    return M.make_inline_sizing_wrap(source_rows)
  end
end

--- Build a single item fragment suitable for `#include` into an existing Typst document.
--- Unlike build_batch_document, this omits document-level header/preamble/page setup.
--- @param item table
--- @param buf_dir string|nil
--- @param source_root string|nil
--- @param effective_root string|nil
--- @param prelude_chunks string[]|nil
--- @return string
function M.build_item_fragment(item, buf_dir, source_root, effective_root, prelude_chunks)
  prelude_chunks = prelude_chunks or state.runtime_preludes

  local do_rewrite = buf_dir ~= nil and source_root ~= nil and effective_root ~= nil
  local pr = do_rewrite and require("math-conceal.image.path-rewrite") or nil
  local function maybe_rewrite(text)
    if pr == nil then
      return text
    end
    return pr.rewrite_paths(text, {
      bufnr = item.bufnr,
      buf_dir = buf_dir,
      source_root = source_root,
      effective_root = effective_root,
    })
  end

  local parts = {}
  if item.requires_mitex == true then
    parts[#parts + 1] = mitex_import_line()
  end
  for i = 1, item.prelude_count or 0 do
    parts[#parts + 1] = maybe_rewrite(prelude_chunks[i] or "")
  end

  local source_rows = item.range[3] - item.range[1] + 1
  local wrap_prefix, wrap_suffix = M.build_wrapper(item, source_rows)
  if wrap_prefix ~= "" then
    parts[#parts + 1] = wrap_prefix
  end
  parts[#parts + 1] = maybe_rewrite(normalize_item_str(item))
  if wrap_suffix ~= "" then
    parts[#parts + 1] = wrap_suffix
  else
    parts[#parts + 1] = "\n"
  end

  return table.concat(parts)
end

--- Build one full-render slot sidecar. The returned map covers only the user
--- body inside the generated sidecar; wrapper/prelude errors intentionally stay
--- attributed to the sidecar file.
--- @param item table
--- @param buf_dir string|nil
--- @param source_root string|nil
--- @param effective_root string|nil
--- @param prelude_chunks string[]|nil
--- @return string, table|nil
function M.build_slot_document(item, buf_dir, source_root, effective_root, prelude_chunks)
  if item.is_tombstone == true then
    return "#box(width: 1pt, height: 1pt)[]\n", nil
  end

  prelude_chunks = prelude_chunks or state.runtime_preludes

  local do_rewrite = buf_dir ~= nil and source_root ~= nil and effective_root ~= nil
  local pr = do_rewrite and require("math-conceal.image.path-rewrite") or nil
  local function maybe_rewrite(text)
    if pr == nil then
      return text
    end
    return pr.rewrite_paths(text, {
      bufnr = item.bufnr,
      buf_dir = buf_dir,
      source_root = source_root,
      effective_root = effective_root,
    })
  end

  local parts = {}
  local cur_line = 1
  local cur_col = 1
  local function append(chunk)
    parts[#parts + 1] = chunk
    cur_line, cur_col = advance_pos(chunk, cur_line, cur_col)
  end

  if item.requires_mitex == true then
    append(mitex_import_line())
  end

  for i = 1, item.prelude_count or 0 do
    append(maybe_rewrite(prelude_chunks[i] or ""))
  end

  local source_rows = item.range[3] - item.range[1] + 1
  local wrap_prefix, wrap_suffix = M.build_wrapper(item, source_rows)
  if wrap_prefix ~= "" then
    append(wrap_prefix)
  end

  local item_text = maybe_rewrite(normalize_item_str(item))
  local gen_start = cur_line
  local gen_start_col = cur_col
  local gen_end_line, gen_end_col_next = advance_pos(item_text, gen_start, gen_start_col)
  append(item_text)

  if wrap_suffix ~= "" then
    append(wrap_suffix)
  else
    append("\n")
  end

  return table.concat(parts),
    {
      gen_start = gen_start,
      gen_end = gen_end_line,
      gen_start_col = gen_start_col,
      gen_end_col = math.max(1, gen_end_col_next - 1),
      bufnr = item.bufnr,
      src_start = item.range[1] + 1,
      src_end = item.range[3] + 1,
      src_start_col = item.range[2] + 1,
      src_end_col = item.range[4] + 1,
      item_idx = item.item_idx,
      slot_id = item.slot_id,
    }
end

--- Build multi-page Typst source for a batch render session.
--- @param items table[]
--- @param buf_dir string|nil   source buffer directory (for path rewriting)
--- @param source_root string|nil  source/project root used for `/...` semantics
--- @param effective_root string|nil  actual Typst root used by the compiler service
--- @param kind "full"|nil  session kind forwarded to get_preamble_file
--- @param prelude_chunks string[]|nil  snapshot of runtime preludes aligned with item.prelude_count
--- @param preamble_include_line string|nil
--- @param build_line_map boolean|nil
--- @param cache table|nil
--- @return string, table
function M.build_batch_document(
  items,
  buf_dir,
  source_root,
  effective_root,
  kind,
  prelude_chunks,
  preamble_include_line,
  build_line_map,
  cache
)
  local main = require("math-conceal.image")
  local config = main.config
  local doc = {}
  local line_map = build_line_map == false and nil or {}
  local cur_line = 1
  local cur_col = 1
  local rep_bufnr = (items[1] and items[1].bufnr) or 0
  prelude_chunks = prelude_chunks or state.runtime_preludes

  local do_rewrite = buf_dir ~= nil and source_root ~= nil and effective_root ~= nil
  local pr = do_rewrite and require("math-conceal.image.path-rewrite") or nil
  local function maybe_rewrite(text)
    if pr == nil then
      return text
    end
    return pr.rewrite_paths(text, {
      bufnr = rep_bufnr,
      buf_dir = buf_dir,
      source_root = source_root,
      effective_root = effective_root,
    })
  end
  local function append_chunk(chunk)
    doc[#doc + 1] = chunk
    cur_line, cur_col = advance_pos(chunk, cur_line, cur_col)
  end

  cache = cache or {}
  cache.item_fragments = cache.item_fragments or {}
  local rewrite_signature = table.concat({
    buf_dir or "",
    source_root or "",
    effective_root or "",
  }, "\0")

  local header_key = table.concat({
    rewrite_signature,
    config.header or "",
    main._styling_prelude or "",
    preamble_include_line or "",
  }, "\0")
  local header_text = cache.header_key == header_key and cache.header_text or nil
  if header_text == nil then
    header_text = build_header_text(config, main, maybe_rewrite, preamble_include_line)
    cache.header_key = header_key
    cache.header_text = header_text
  end
  append_chunk(header_text)
  if header_text ~= "" then
    append_chunk("#pagebreak(weak: true)\n")
  end

  for idx, item in ipairs(items) do
    if idx > 1 then
      append_chunk("#pagebreak()\n")
    end

    local source_rows = item.range[3] - item.range[1] + 1
    local wrap_prefix, wrap_suffix = M.build_wrapper(item, source_rows)
    local suffix_text = wrap_suffix ~= "" and wrap_suffix or "\n"
    local item_import = item.requires_mitex == true and mitex_import_line() or ""
    local item_key = table.concat({
      rewrite_signature,
      tostring(prelude_chunks),
      tostring(item.prelude_count or 0),
      item_import,
      wrap_prefix,
      suffix_text,
      normalize_item_str(item),
    }, "\0")
    local item_cache = cache.item_fragments[item_key]
    if item_cache == nil then
      local prefix_parts = {}
      if item_import ~= "" then
        prefix_parts[#prefix_parts + 1] = item_import
      end
      for i = 1, item.prelude_count do
        prefix_parts[#prefix_parts + 1] = maybe_rewrite(prelude_chunks[i] or "")
      end
      if wrap_prefix ~= "" then
        prefix_parts[#prefix_parts + 1] = wrap_prefix
      end
      local item_text = maybe_rewrite(normalize_item_str(item))
      item_cache = {
        prefix = table.concat(prefix_parts),
        item_text = item_text,
        suffix = suffix_text,
      }
      cache.item_fragments[item_key] = item_cache
    end

    if item_cache.prefix ~= "" then
      append_chunk(item_cache.prefix)
    end

    local gen_start = cur_line
    local gen_start_col = cur_col
    local gen_end_line, gen_end_col_next = advance_pos(item_cache.item_text, gen_start, gen_start_col)
    local gen_end = gen_end_line
    append_chunk(item_cache.item_text)

    local src_start_col = item.range[2] + 1
    local src_end_col = item.range[4] + 1
    local gen_end_col = math.max(1, gen_end_col_next - 1)

    if line_map ~= nil then
      line_map[#line_map + 1] = {
        gen_start = gen_start,
        gen_end = gen_end,
        gen_start_col = gen_start_col,
        gen_end_col = gen_end_col,
        bufnr = item.bufnr,
        src_start = item.range[1] + 1,
        src_end = item.range[3] + 1,
        src_start_col = src_start_col,
        src_end_col = src_end_col,
        item_idx = idx,
      }
    end

    append_chunk(item_cache.suffix)
  end

  return table.concat(doc), line_map
end

return M
