---wrap lua module written in rust. independent from neovim.
local M = {}

local lookup_conceal = require 'lookup_conceal'

--- Function to convert LaTeX math symbols to Unicode
--- @param text string: The LaTeX math symbol to convert
--- @param pattern '"escape"'|'"conceal"'|'"font"'|'"sub"'|'"sup"' Valid values from PatternType enum
--- @param type? string: Type of concealment (e.g., "cal", "frak", "bold", etc.)
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_math_symbol(text, pattern, type)
  return lookup_conceal.lookup_math_symbol({ text = text, pattern = pattern or "conceal", mode = type or "" })
      or text
end

--- Batch lookup function for better performance
--- @param batch table: Array of {text, pattern, mode} tables
--- @return table: Array of results
function M.lookup_batch(batch)
  return lookup_conceal.lookup_batch(batch) or batch
end

--- Lookup all math symbols with any patterns and any types
--- Warning: This can be slow for large input
--- @param text string: The LaTeX math symbol to convert
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_all(text)
  local pattern, type
  if text:sub(1, 1) == "\\" then
    local brace_start = text:find("{", 2, true)
    local brace_end = text:find("}", brace_start, true)
    if brace_start and brace_end and brace_start > 2 then
      local cmd = text:sub(1, brace_start - 1)
      local arg = text:sub(brace_start + 1, brace_end - 1)
      pattern = "font"
      type = cmd
      text = arg
    else
      pattern = "conceal"
      type = ""
    end
  end
  ---SAFETY: If pattern or type is nil, return the original text
  if pattern == nil or type == nil then
    return text
  end
  return lookup_conceal.lookup_math_symbol({ text = text, pattern = pattern, mode = type }) or text
end

return M
