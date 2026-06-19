local M = {}

local function count_lines(text)
  if text == nil or text == "" then
    return 0
  end
  local _, n = text:gsub("\n", "\n")
  if text:sub(-1) ~= "\n" then
    n = n + 1
  end
  return n
end

local function advance_pos(text, line, col)
  if text == nil or text == "" then
    return line, col
  end
  local idx = 1
  while true do
    local nl = text:find("\n", idx, true)
    if nl == nil then
      return line, col + (#text - idx + 1)
    end
    line = line + 1
    col = 1
    idx = nl + 1
  end
end

local function typst_string_literal(value)
  value = value or ""
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  return '"' .. value .. '"'
end

local function mitex_import_line(ctx)
  local package = ctx.mitex_package or "@preview/mitex:0.2.7"
  if package == "" then
    return ""
  end
  return '#import "' .. package .. '": mitex, mi\n'
end

local function rewrite(ctx, bufnr, text)
  if text == nil or text == "" then
    return text or ""
  end
  return require("math-conceal.image.path-rewrite").rewrite_paths(text, {
    bufnr = bufnr,
    buf_dir = ctx.buf_dir,
    source_root = ctx.source_root,
    effective_root = ctx.effective_root,
  })
end

function M.count_lines(text)
  return count_lines(text)
end

function M.build_context_document(config, ctx)
  local parts = {}
  if type(ctx.header) == "string" and ctx.header ~= "" then
    parts[#parts + 1] = rewrite(ctx, ctx.bufnr, ctx.header) .. "\n"
  end
  parts[#parts + 1] = config._styling_prelude or ""
  if ctx.wrapper == "mitex" then
    parts[#parts + 1] = mitex_import_line(ctx)
  end
  if type(ctx.preamble_include_line) == "string" and ctx.preamble_include_line ~= "" then
    parts[#parts + 1] = ctx.preamble_include_line
  end
  return table.concat(parts)
end

function M.build_flow_context_document(ctx)
  local parts = {}
  if type(ctx.header) == "string" and ctx.header ~= "" then
    parts[#parts + 1] = rewrite(ctx, ctx.bufnr, ctx.header) .. "\n"
  end
  if ctx.wrapper == "mitex" then
    parts[#parts + 1] = mitex_import_line(ctx)
  end
  if type(ctx.preamble_include_line) == "string" and ctx.preamble_include_line ~= "" then
    parts[#parts + 1] = ctx.preamble_include_line
  end
  return table.concat(parts)
end

local function baseline_pt(config)
  local baseline = tonumber(config and config.math_baseline_pt) or 11
  if baseline <= 0 then
    baseline = 11
  end
  return baseline
end

function M.editor_size_prelude(config)
  local baseline = baseline_pt(config)
  return string.format("#set text(size: %gpt)\n#show math.equation: set text(size: %gpt)\n", baseline, baseline)
end

function M.render_size_key(config)
  return tostring(baseline_pt(config))
end

local function flow_block_config(ctx)
  local cfg = (ctx and ctx.code_block) or {}
  return {
    padding_cols = cfg.padding_cols ~= nil and tonumber(cfg.padding_cols) or 15,
    margin_pt = cfg.margin_pt ~= nil and tonumber(cfg.margin_pt) or 6,
    min_cols = cfg.min_cols ~= nil and tonumber(cfg.min_cols) or 8,
  }
end

local function flow_block_layout(bufnr, ctx, config)
  local state = require("math-conceal.image.state")
  local cfg = flow_block_config(ctx)
  local baseline = baseline_pt(config)
  local pad_cols = math.max(0, cfg.padding_cols or 15)
  local min_cols = math.max(1, cfg.min_cols or 8)
  local win_cols = state.visible_window_width(bufnr)
  local usable_cols = math.max(min_cols, win_cols - 2 * pad_cols)
  local cell_w, cell_h = state.cell_size()
  local cell_w_pt
  if cell_w ~= nil and cell_h ~= nil then
    cell_w_pt = baseline * (cell_w / cell_h)
  else
    cell_w_pt = baseline * 0.55
  end
  return {
    baseline = baseline,
    pad_cols = pad_cols,
    margin_pt = math.max(0, cfg.margin_pt or 6),
    min_cols = min_cols,
    win_cols = win_cols,
    usable_cols = usable_cols,
    cell_w = cell_w,
    cell_h = cell_h,
    page_w_pt = usable_cols * cell_w_pt,
  }
end

function M.flow_block_wrap(bufnr, ctx, config)
  local layout = flow_block_layout(bufnr, ctx, config or {})
  return string.format(
    "#context {\n"
      .. "  set page(width: %gpt, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n"
      .. "  set text(size: %gpt)\n"
      .. "  block(width: 100%%, inset: (x: %gpt, y: 0pt))[\n",
    layout.page_w_pt,
    layout.baseline,
    layout.margin_pt
  ),
    "  ]\n}\n"
end

local function code_render_policy(track)
  if (track.object_kind or track.node_type) ~= "code" then
    return nil
  end
  local facts = track.source_facts or {}
  if facts.render_policy ~= nil and facts.render_policy ~= "" then
    return facts.render_policy
  end
  if track.source_display_kind == "inline" then
    return "inline_naturalized"
  end
  if track.source_display_kind == "block" then
    return "block_constrained"
  end
  return nil
end

function M.render_layout_key(track, ctx, config)
  local render_policy = code_render_policy(track)
  if render_policy == "block_constrained" or render_policy == "block" then
    local layout = flow_block_layout(track.bufnr, ctx, config or {})
    return table.concat({
      "code-block-flow-v2",
      tostring(layout.baseline),
      tostring(layout.pad_cols),
      tostring(layout.margin_pt),
      tostring(layout.min_cols),
      tostring(layout.win_cols),
      tostring(layout.usable_cols),
      tostring(layout.cell_w or ""),
      tostring(layout.cell_h or ""),
      tostring(layout.page_w_pt),
    }, "\0")
  end
  if render_policy == "inline_naturalized" then
    return "code-inline-naturalized-v1"
  end
  return ""
end

local function inline_naturalize_prelude(enabled)
  if enabled ~= true then
    return ""
  end
  return [[#let __math_conceal_natural_box(it) = {
  let __w = it.width
  let __relative = type(__w) == relative and __w.ratio != 0%
  let __fraction = type(__w) == fraction
  if __relative or __fraction {
    box(
      fill: it.fill,
      stroke: it.stroke,
      radius: it.radius,
      inset: it.inset,
      outset: it.outset,
      baseline: it.baseline,
      clip: it.clip,
    )[#it.body]
  } else {
    it
  }
}
#show box: __math_conceal_natural_box
]]
end

function M.inline_wrap(config, source_rows, opts)
  opts = opts or {}
  local state = require("math-conceal.image.state")
  local cell_w, cell_h = state.cell_size()
  local baseline = baseline_pt(config)
  local naturalize = inline_naturalize_prelude(opts.naturalize == true)
  if cell_h ~= nil and cell_w ~= nil then
    local cell_w_pt = baseline * (cell_w / cell_h)
    if source_rows == 1 then
      return "#context { let __it = [" .. naturalize,
        string.format(
          "]; let __d = measure(__it); let __mh = %gpt; let __mw = %gpt;"
            .. " let __rows = __d.height / __mh;"
            .. " if __rows <= 1.5 { block(width: __d.width, height: __mh, clip: true, align(horizon, __it)) }"
            .. " else { let __r = calc.max(1, calc.ceil(__rows - 0.001));"
            .. " block(width: __d.width, height: __r * __mh, align(horizon, __it)) } }\n",
          baseline,
          cell_w_pt
        )
    end

    return "#context { let __it = [" .. naturalize,
      string.format(
        "]; let __d = measure(__it); let __mh = %gpt; let __mw = %gpt;"
          .. " let __rows = calc.max(1, calc.ceil(__d.height / __mh - 0.001));"
          .. " let __cols = calc.max(1, calc.ceil(__d.width / __mw - 0.001));"
          .. " let __th = __rows * __mh; let __tw = __cols * __mw;"
          .. " block(width: __tw, height: __th, align(horizon, __it)) }\n",
        baseline,
        cell_w_pt
      )
  end
  return "", ""
end

local markdown_delimiters = {
  dollar_inline = { open = "$", close = "$", display_kind = "inline" },
  dollar_block = { open = "$$", close = "$$", display_kind = "block" },
  paren_inline = { open = "\\(", close = "\\)", display_kind = "inline" },
  bracket_block = { open = "\\[", close = "\\]", display_kind = "block" },
}

local function markdown_math_content(track)
  local source = track.source or ""
  local facts = track.source_facts or {}
  local delimiter = markdown_delimiters[facts.delimiter]
  if delimiter == nil then
    return source, facts.display_kind or track.source_display_kind or "inline"
  end

  local content = source
  if source:sub(1, #delimiter.open) == delimiter.open and source:sub(-#delimiter.close) == delimiter.close then
    content = source:sub(#delimiter.open + 1, #source - #delimiter.close)
  end
  if delimiter.display_kind == "block" then
    content = content:gsub("^\n", ""):gsub("\n$", "")
  end
  return content, delimiter.display_kind
end

local function render_input(track, ctx)
  if (track.object_kind or track.node_type) == "code" then
    local source = rewrite(ctx, track.bufnr, track.source or "")
    if track.source_display_kind == "inline" then
      source = source:gsub("[ \t\r]*\n[ \t\r]*", " ")
      source = source:gsub("%[%s+", "["):gsub("%s+%]", "]")
    end
    return source
  end

  if ctx.wrapper ~= "mitex" then
    return rewrite(ctx, track.bufnr, track.source or "")
  end

  local content, display_kind = markdown_math_content(track)
  local call = display_kind == "block" and "mitex" or "mi"
  return "#" .. call .. "(" .. typst_string_literal(content) .. ")"
end

function M.build_slot_document(track, ctx, config)
  local parts = {}
  local cur_line, cur_col = 1, 1
  local function append(text)
    parts[#parts + 1] = text
    cur_line, cur_col = advance_pos(text, cur_line, cur_col)
  end

  if ctx.wrapper == "mitex" then
    append(mitex_import_line(ctx))
  end

  local prelude_count = math.max(0, math.min(track.prelude_count or 0, #(ctx.context_units or {})))
  for idx = 1, prelude_count do
    append(rewrite(ctx, track.bufnr, ctx.context_units[idx].source or ""))
    if not (parts[#parts] or ""):match("\n$") then
      append("\n")
    end
  end

  local source_rows = track.source_rows or math.max(1, track.end_row - track.row + 1)
  local render_policy = code_render_policy(track)
  local is_code_block = render_policy == "block_constrained" or render_policy == "block"
  local prefix, suffix = "", ""
  if is_code_block then
    prefix, suffix = M.flow_block_wrap(track.bufnr, ctx, config)
  else
    prefix, suffix = M.inline_wrap(config, source_rows, {
      naturalize = render_policy == "inline_naturalized",
    })
  end
  if prefix ~= "" then
    append(prefix)
  end

  append(M.editor_size_prelude(config))

  local gen_start = cur_line
  local gen_start_col = cur_col
  local source = render_input(track, ctx)
  local gen_end, gen_end_col_next = advance_pos(source, gen_start, gen_start_col)
  append(source)

  if suffix ~= "" then
    append(suffix)
  else
    append("\n")
  end

  return table.concat(parts),
    {
      gen_start = gen_start,
      gen_end = gen_end,
      gen_start_col = gen_start_col,
      gen_end_col = math.max(1, gen_end_col_next - 1),
      bufnr = track.bufnr,
      src_start = track.row + 1,
      src_end = track.end_row + 1,
      src_start_col = track.col + 1,
      src_end_col = track.end_col + 1,
      item_idx = track.track_id,
    }
end

function M.build_flow_source(track, ctx)
  local parts = {}
  local len = 0
  local function append(text)
    text = text or ""
    parts[#parts + 1] = text
    len = len + #text
    if not text:match("\n$") then
      parts[#parts + 1] = "\n"
      len = len + 1
    end
  end

  local prelude_count = math.max(0, math.min(track.prelude_count or 0, #(ctx.context_units or {})))
  for idx = 1, prelude_count do
    append(rewrite(ctx, track.bufnr, ctx.context_units[idx].source or ""))
  end

  -- Flow/layout probes must be syntactically self-contained.  Context units
  -- above provide the Typst prelude, but arbitrary buffer prefixes can contain
  -- half-open math/code delimiters and must not be replayed into the probe.
  local prefix = "x "
  local source = render_input(track, ctx)
  parts[#parts + 1] = prefix
  len = len + #prefix
  local target_start = len
  parts[#parts + 1] = source
  len = len + #source
  local target_end = len
  if not source:match("\n$") then
    parts[#parts + 1] = "\n"
  end
  return table.concat(parts), {
    target_start = target_start,
    target_end = target_end,
  }
end

return M
