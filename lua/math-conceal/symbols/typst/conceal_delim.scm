; Typst delimiter conceals
; Math delimiters - parentheses, brackets, braces
((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "lr")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal ""))

((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "floor")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "⌊")
  (#set! @right_brace conceal "⌋"))

((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "ceil")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "⌈")
  (#set! @right_brace conceal "⌉"))

((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "round")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "⌊")
  (#set! @right_brace conceal "⌉"))

((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "norm")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "║")
  (#set! @right_brace conceal "║"))

((call
  item: (ident) @typ_math_delim
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @typ_math_delim "abs")
  (#has-ancestor? @typ_math_delim math formula)
  (#not-has-parent? @typ_math_delim field)
  (#set! @typ_math_delim conceal "")
  (#set! @left_brace conceal "￨")
  (#set! @right_brace conceal "￨"))

([
  (ident)
  (field)
] @typ_math_delim
  (#any-of? @typ_math_delim
    "angle.curly" "angle.curly.l" "angle.curly.r" "angle.dot" "angle.dot.l" "angle.dot.r"
    "angle.double" "angle.double.l" "angle.double.r" "angle.l" "angle.l.curly" "angle.l.dot"
    "angle.l.double" "angle.r" "angle.r.curly" "angle.r.dot" "angle.r.double" "bar" "bar.broken"
    "bar.broken.v" "bar.double" "bar.double.v" "bar.triple" "bar.triple.v" "bar.v" "bar.v.broken"
    "bar.v.double" "bar.v.triple" "brace" "brace.double" "brace.double.l" "brace.double.r" "brace.l"
    "brace.l.double" "brace.l.stroked" "brace.r" "brace.r.double" "brace.r.stroked" "brace.stroked"
    "brace.stroked.l" "brace.stroked.r" "bracket" "bracket.double" "bracket.double.l"
    "bracket.double.r" "bracket.l" "bracket.l.double" "bracket.l.stroked" "bracket.r"
    "bracket.r.double" "bracket.r.stroked" "bracket.stroked" "bracket.stroked.l" "bracket.stroked.r"
    "ceil" "ceil.l" "ceil.r" "chevron" "chevron.closed" "chevron.closed.l" "chevron.closed.r"
    "chevron.curly" "chevron.curly.l" "chevron.curly.r" "chevron.dot" "chevron.dot.l"
    "chevron.dot.r" "chevron.double" "chevron.double.l" "chevron.double.r" "chevron.l"
    "chevron.l.closed" "chevron.l.curly" "chevron.l.dot" "chevron.l.double" "chevron.r"
    "chevron.r.closed" "chevron.r.curly" "chevron.r.dot" "chevron.r.double" "fence" "fence.dotted"
    "fence.double" "fence.double.l" "fence.double.r" "fence.l" "fence.l.double" "fence.r"
    "fence.r.double" "floor" "floor.l" "floor.r" "mustache" "mustache.l" "mustache.r" "paren"
    "paren.closed" "paren.closed.l" "paren.closed.r" "paren.double" "paren.double.l"
    "paren.double.r" "paren.flat" "paren.flat.l" "paren.flat.r" "paren.l" "paren.l.closed"
    "paren.l.double" "paren.l.flat" "paren.l.stroked" "paren.r" "paren.r.closed" "paren.r.double"
    "paren.r.flat" "paren.r.stroked" "paren.stroked" "paren.stroked.l" "paren.stroked.r" "shell"
    "shell.double" "shell.double.l" "shell.double.r" "shell.filled" "shell.filled.l"
    "shell.filled.r" "shell.l" "shell.l.double" "shell.l.filled" "shell.l.stroked" "shell.r"
    "shell.r.double" "shell.r.filled" "shell.r.stroked" "shell.stroked" "shell.stroked.l"
    "shell.stroked.r")
  (#not-has-parent? @typ_math_delim field call)
  (#has-ancestor? @typ_math_delim math)
  (#set-conceal! @typ_math_delim "conceal"))

((symbol) @typ_math_delim
  (#any-of? @typ_math_delim "|" "||" "|]")
  (#has-ancestor? @typ_math_delim math)
  (#set-conceal! @typ_math_delim "conceal"))

; `(` and `)` alias for all brackets
("(" @typ_math_delim
  (#any-of? @typ_math_delim "[|")
  (#has-ancestor? @typ_math_delim math)
  (#set-conceal! @typ_math_delim "conceal"))

(math
  "$" @typ_inline_dollar
  (#set! @typ_inline_dollar conceal ""))

(string
  "\"" @typ_inline_quote
  (#has-ancestor? @typ_inline_quote math)
  (#set! @typ_inline_quote conceal ""))

(strong
  "*" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))

(emph
  "_" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))

(raw_span
  "`" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))

(raw_blck
  "```" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))

((align
  "&" @typ_inline_ampersand)
  (#set! @typ_inline_ampersand conceal ""))

(item
  "-" @conceal
  (#set! @conceal conceal "•"))
