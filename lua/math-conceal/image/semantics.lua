--- Unified render semantics classification for typst-concealer.
--- Replaces the old is_block_formula() + classify_layout_kind() pair with a single
--- orthogonal structure that decouples Typst wrapper choice from Neovim display strategy.
local M = {}

--- @alias ConstraintKind "intrinsic" | "flow"
--- @alias DisplayKind    "inline"    | "block"
--- @alias SourceKind     "math"      | "code"

--- @class RenderSemantics
--- @field constraint_kind ConstraintKind  -- "flow": Typst page-width wrapper; "intrinsic": cell-snapping wrapper
--- @field display_kind    DisplayKind     -- "block": centred/padded extmark; "inline": inline extmark
--- @field source_kind     SourceKind      -- original treesitter node type
--- @field render_whole_line? boolean      -- single-line Typst display math embedded in markup; render the whole source line

--- Classify the render semantics of a Typst node.
---
--- Mapping:
---   math inline  → intrinsic + inline
---   math block   → intrinsic + block
---   code inline  → intrinsic + inline
---   code block   → flow      + block
---
--- @param range  Range4
--- @param bufnr  integer
--- @param node_type SourceKind
--- @return RenderSemantics
function M.classify(range, bufnr, node_type)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local is_multiline = end_row > start_row

  -- Typst wrapper decision: multiline code needs a page-width wrapper so that
  -- the rendered content fills the available column width correctly.
  local constraint_kind = (node_type == "code" and is_multiline) and "flow" or "intrinsic"

  -- Neovim display decision: block = centred or left-padded image extmark.
  local display_kind
  local render_whole_line = false
  if is_multiline then
    display_kind = "block"
  elseif node_type == "math" then
    local line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ""
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local formula_text = line:sub(start_col + 1, end_col)

    if trimmed == formula_text then
      -- Single-line math occupying the whole trimmed line.
      display_kind = "block"
    elseif formula_text:match("^%$%s+") and formula_text:match("%s+%$$") then
      -- Typst treats `$ ... $` with inner-edge whitespace as display math even
      -- when it appears inside surrounding markup. Keep the existing math node
      -- capture, but upgrade it at render/display time to a whole-line block.
      display_kind = "block"
      render_whole_line = true
    else
      display_kind = "inline"
    end
  else
    display_kind = "inline"
  end

  return {
    constraint_kind = constraint_kind,
    display_kind = display_kind,
    source_kind = node_type,
    render_whole_line = render_whole_line,
  }
end

return M
