--- Markdown math source adapter.
--- Collects LaTeX math ranges and converts them to Typst/MiTeX render text.

local M = {}

function M.render_viewport()
  return {
    kind = "visible",
    margin = 0,
  }
end

function M.render_policy()
  return {
    kind = "progressive",
    margin = 0,
  }
end

local function is_escaped(line, idx)
  local slash_count = 0
  local pos = idx - 1
  while pos >= 1 and line:sub(pos, pos) == "\\" do
    slash_count = slash_count + 1
    pos = pos - 1
  end
  return slash_count % 2 == 1
end

local function find_unescaped(line, needle, init)
  local pos = init or 1
  while true do
    local found = line:find(needle, pos, true)
    if found == nil then
      return nil
    end
    if not is_escaped(line, found) then
      return found
    end
    pos = found + #needle
  end
end

local function typst_string_literal(value)
  value = value or ""
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  return '"' .. value .. '"'
end

local function render_text(content, display_kind)
  if display_kind == "block" then
    return "#mitex(" .. typst_string_literal(content) .. ")"
  end
  return "#mi(" .. typst_string_literal(content) .. ")"
end

local function original_text(lines, range)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  if start_row == end_row then
    return (lines[start_row + 1] or ""):sub(start_col + 1, end_col)
  end

  local parts = {}
  parts[1] = (lines[start_row + 1] or ""):sub(start_col + 1)
  for row = start_row + 1, end_row - 1 do
    parts[#parts + 1] = lines[row + 1] or ""
  end
  parts[#parts + 1] = (lines[end_row + 1] or ""):sub(1, end_col)
  return table.concat(parts, "\n")
end

local function block_content(lines, start_row, start_col, end_row, end_col)
  if start_row == end_row then
    return (lines[start_row + 1] or ""):sub(start_col + 3, end_col - 2)
  end

  local parts = {}
  parts[1] = (lines[start_row + 1] or ""):sub(start_col + 3)
  for row = start_row + 1, end_row - 1 do
    parts[#parts + 1] = lines[row + 1] or ""
  end
  parts[#parts + 1] = (lines[end_row + 1] or ""):sub(1, end_col - 2)
  if parts[1] == "" then
    table.remove(parts, 1)
  end
  if parts[#parts] == "" then
    parts[#parts] = nil
  end
  return table.concat(parts, "\n")
end

local function push_entry(entries, lines, range, content, display_kind)
  entries[#entries + 1] = {
    range = range,
    display_range = range,
    prelude_count = 0,
    node_type = "math",
    source_text = original_text(lines, range),
    render_text = render_text(content, display_kind),
    stable_key = table.concat(range, ":"),
    semantics = {
      constraint_kind = "intrinsic",
      display_kind = display_kind,
      source_kind = "math",
      markdown_math = true,
    },
    requires_mitex = true,
  }
end

local function collect_inline_math(entries, lines, row)
  local line = lines[row + 1] or ""
  local pos = 1
  while pos <= #line do
    local start_pos = find_unescaped(line, "$", pos)
    if start_pos == nil then
      return
    end

    if line:sub(start_pos, start_pos + 1) == "$$" then
      local end_pos = find_unescaped(line, "$$", start_pos + 2)
      if end_pos ~= nil then
        local range = { row, start_pos - 1, row, end_pos + 1 }
        local content = line:sub(start_pos + 2, end_pos - 1)
        push_entry(entries, lines, range, content, "block")
        pos = end_pos + 2
      else
        pos = start_pos + 2
      end
    else
      local end_pos = find_unescaped(line, "$", start_pos + 1)
      if end_pos == nil then
        return
      end
      if end_pos > start_pos + 1 then
        local range = { row, start_pos - 1, row, end_pos }
        local content = line:sub(start_pos + 1, end_pos - 1)
        push_entry(entries, lines, range, content, "inline")
      end
      pos = end_pos + 1
    end
  end
end

--- @param bufnr integer
--- @return table[]
function M.collect(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = {}
  local row = 0
  local in_fence = false

  while row < #lines do
    local line = lines[row + 1] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_fence = not in_fence
      row = row + 1
    elseif in_fence then
      row = row + 1
    else
      local block_start = line:find("%$%$", 1)
      if block_start ~= nil and not is_escaped(line, block_start) then
        local end_row = row
        local end_col = nil
        local same_line_end = find_unescaped(line, "$$", block_start + 2)
        if same_line_end ~= nil then
          end_col = same_line_end + 1
        else
          local scan = row + 1
          while scan < #lines do
            local close_pos = find_unescaped(lines[scan + 1] or "", "$$", 1)
            if close_pos ~= nil then
              end_row = scan
              end_col = close_pos + 1
              break
            end
            scan = scan + 1
          end
        end

        if end_col ~= nil then
          local range = { row, block_start - 1, end_row, end_col }
          local content = block_content(lines, row, block_start - 1, end_row, end_col)
          push_entry(entries, lines, range, content, "block")
          row = end_row + 1
        else
          collect_inline_math(entries, lines, row)
          row = row + 1
        end
      else
        collect_inline_math(entries, lines, row)
        row = row + 1
      end
    end
  end

  return entries
end

return M
