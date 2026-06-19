local kitty_codes = require("math-conceal.image.kitty-codes")

local M = {}

local function buf_win(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
end

local function resolve_win(bufnr, opts)
  local winid = opts and opts.winid or nil
  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
  return buf_win(bufnr)
end

local function window_text_width(winid)
  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    local info = vim.fn.getwininfo(winid)[1] or {}
    local textoff = tonumber(info.textoff) or 0
    return math.max(1, vim.api.nvim_win_get_width(winid) - textoff)
  end
  return math.max(1, vim.o.columns)
end

local function window_layout(bufnr, opts)
  local winid = resolve_win(bufnr, opts)
  local wo = winid ~= nil and vim.wo[winid] or vim.wo
  local bo = bufnr ~= nil and vim.bo[bufnr] or vim.bo
  return {
    winid = winid,
    text_width = window_text_width(winid),
    wrap = wo.wrap == true,
    linebreak = wo.linebreak == true,
    breakindent = wo.breakindent == true,
    showbreak = tostring(wo.showbreak or ""),
    breakat = tostring(vim.o.breakat or ""),
    tabstop = tonumber(bo.tabstop) or tonumber(vim.o.tabstop) or 8,
  }
end

function M.layout_key(bufnr, opts)
  local layout = window_layout(bufnr, opts)
  return table.concat({
    tostring(layout.wrap),
    tostring(layout.text_width),
    tostring(layout.linebreak),
    tostring(layout.breakindent),
    layout.showbreak,
    layout.breakat,
    tostring(layout.tabstop),
    tostring(vim.o.ambiwidth or ""),
    tostring(vim.o.display or ""),
  }, "\31")
end

local function append_chunk(line, text, hl)
  if text == nil or text == "" then
    return
  end
  hl = hl or ""
  local last = line[#line]
  if last ~= nil and vim.deep_equal(last[2], hl) then
    last[1] = (last[1] or "") .. text
  else
    line[#line + 1] = { text, hl }
  end
end

local function first_char(text)
  return vim.fn.strcharpart(text or "", 0, 1)
end

local function is_break_char(text, layout)
  if not layout.linebreak then
    return false
  end
  local ch = first_char(text)
  return ch ~= "" and #ch == 1 and layout.breakat:find(ch, 1, true) ~= nil
end

local function is_indent_char(text)
  local ch = first_char(text)
  return ch == " " or ch == "\t"
end

local function contains_placeholder(text)
  return type(text) == "string" and text:find(kitty_codes.placeholder, 1, true) ~= nil
end

local function token_width(token, col)
  return vim.fn.strdisplaywidth(token.text or "", col or 0)
end

local function line_width(tokens, start_idx, end_idx, start_col)
  local col = start_col or 0
  for idx = start_idx, end_idx do
    col = col + token_width(tokens[idx], col)
  end
  return col - (start_col or 0)
end

local function line_tokens_to_chunks(tokens, start_idx, end_idx, prefix)
  local line = {}
  for _, chunk in ipairs(prefix or {}) do
    append_chunk(line, chunk[1], chunk[2])
  end
  for idx = start_idx, end_idx do
    local token = tokens[idx]
    append_chunk(line, token.text, token.hl)
  end
  if #line == 0 then
    line[1] = { "", "" }
  end
  return line
end

local function split_text_tokens(text, hl, layout)
  local tokens = {}
  local char_count = vim.fn.strchars(text or "")
  for idx = 0, char_count - 1 do
    local ch = vim.fn.strcharpart(text, idx, 1)
    local ch_width = vim.fn.strdisplaywidth(ch, 0)
    local last = tokens[#tokens]
    if ch_width == 0 and last ~= nil then
      last.text = last.text .. ch
    else
      tokens[#tokens + 1] = {
        text = ch,
        hl = hl or "",
        break_after = is_break_char(ch, layout),
      }
    end
  end
  return tokens
end

local function split_chunk_tokens(chunk, layout)
  local text = chunk and chunk[1] or ""
  if text == "" then
    return {}
  end
  local hl = chunk[2] or ""
  if chunk.atomic == true or chunk.image == true or contains_placeholder(text) then
    return {
      {
        text = text,
        hl = hl,
        atomic = true,
        break_after = false,
      },
    }
  end
  return split_text_tokens(text, hl, layout)
end

local function line_tokens(chunks, layout)
  local tokens = {}
  for _, chunk in ipairs(chunks or {}) do
    for _, token in ipairs(split_chunk_tokens(chunk, layout)) do
      tokens[#tokens + 1] = token
    end
  end
  return tokens
end

local function prefix_width(prefix)
  local col = 0
  for _, chunk in ipairs(prefix or {}) do
    col = col + vim.fn.strdisplaywidth(chunk[1] or "", col)
  end
  return col
end

local function leading_indent_width(tokens)
  local col = 0
  for _, token in ipairs(tokens or {}) do
    if not is_indent_char(token.text) then
      break
    end
    col = col + token_width(token, col)
  end
  return col
end

local function continuation_prefix(tokens, layout)
  local prefix = {}
  if layout.showbreak ~= "" then
    prefix[#prefix + 1] = { layout.showbreak, "NonText" }
  end
  if layout.breakindent then
    local showbreak_width = prefix_width(prefix)
    local indent = math.max(0, math.min(leading_indent_width(tokens), layout.text_width - showbreak_width - 1))
    if indent > 0 then
      prefix[#prefix + 1] = { string.rep(" ", indent), "" }
    end
  end
  if prefix_width(prefix) >= layout.text_width then
    return {}
  end
  return prefix
end

local function slice_fits(tokens, start_idx, end_idx, prefix_col, max_cols)
  return prefix_col + line_width(tokens, start_idx, end_idx, prefix_col) <= max_cols
end

local function choose_line_end(tokens, start_idx, prefix_col, layout)
  local max_cols = layout.text_width
  local col = prefix_col
  local last_break = nil
  local idx = start_idx

  while idx <= #tokens do
    local width = token_width(tokens[idx], col)
    if width > 0 and col > prefix_col and col + width > max_cols then
      if layout.linebreak and last_break ~= nil and last_break >= start_idx then
        return last_break
      end
      return idx - 1
    end

    col = col + width
    if tokens[idx].break_after == true then
      last_break = idx
    end
    idx = idx + 1
  end

  return #tokens
end

local function wrap_one_line(chunks, layout)
  local tokens = line_tokens(chunks, layout)
  if #tokens == 0 then
    return { { { "", "" } } }
  end

  local lines = {}
  local idx = 1
  local continuation = false
  local prefix = {}

  while idx <= #tokens do
    prefix = continuation and continuation_prefix(tokens, layout) or {}
    local pwidth = prefix_width(prefix)
    local end_idx = choose_line_end(tokens, idx, pwidth, layout)
    if end_idx < idx then
      end_idx = idx
    end
    if tokens[end_idx].atomic and not slice_fits(tokens, idx, end_idx, pwidth, layout.text_width) and end_idx > idx then
      end_idx = end_idx - 1
    end
    if end_idx < idx then
      end_idx = idx
    end

    lines[#lines + 1] = line_tokens_to_chunks(tokens, idx, end_idx, prefix)
    idx = end_idx + 1
    continuation = true
  end

  return lines
end

-- HACK: best-effort virtual-line wrapping.
--
-- Neovim explicitly does not apply 'wrap' or 'linebreak' to virt_lines, and it
-- does not expose an API that maps arbitrary highlighted chunks back through
-- the native screen-line layout engine.  This shim is intentionally isolated
-- from the Formula Display Projection renderer: it approximates user-visible
-- wrapping by display-cell width, respects the relevant window options where
-- practical, and leaves image placeholder chunks atomic so the terminal image
-- protocol is not split across lines.
function M.wrap_virt_lines(bufnr, lines, opts)
  local layout = window_layout(bufnr, opts)
  if not layout.wrap then
    return lines
  end

  local out = {}
  for _, line in ipairs(lines or {}) do
    for _, wrapped in ipairs(wrap_one_line(line, layout)) do
      out[#out + 1] = wrapped
    end
  end

  if #out == 0 then
    return { { { "", "" } } }
  end
  return out
end

return M
