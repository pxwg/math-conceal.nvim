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
  parts[#parts + 1] = mitex_import_line(ctx)
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

function M.inline_wrap(config, source_rows)
  local state = require("math-conceal.image.state")
  local cell_w, cell_h = state.cell_size()
  local baseline = baseline_pt(config)
  if cell_h ~= nil and cell_w ~= nil then
    local cell_w_pt = baseline * (cell_w / cell_h)
    if source_rows == 1 then
      return "#context { let __it = [",
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

    return "#context { let __it = [",
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

local function render_input(track)
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

  append(mitex_import_line(ctx))

  local source_rows = track.source_rows or math.max(1, track.end_row - track.row + 1)
  local prefix, suffix = M.inline_wrap(config, source_rows)
  if prefix ~= "" then
    append(prefix)
  end

  append(M.editor_size_prelude(config))

  local gen_start = cur_line
  local gen_start_col = cur_col
  local source = render_input(track)
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

return M
