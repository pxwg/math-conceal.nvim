; Typst delimiter conceals
; Math delimiters - parentheses, brackets, braces
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "lr" "left" "right")
  (#has-ancestor? @typ_math_delim math formula)
  (#set! conceal ""))

; Angle brackets
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "angle" "langle" "rangle")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Floor and ceiling
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "floor" "ceil" "lfloor" "rfloor" "lceil" "rceil")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Norm delimiters
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "norm")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Vertical bars and double bars
((symbol) @typ_math_delim
  (#any-of? @typ_math_delim "|" "||")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Inline math dollars and quotes
(math
  "$" @typ_inline_dollar
  (#set! @typ_inline_dollar conceal ""))

(string
  "\"" @typ_inline_quote
  (#set! @typ_inline_quote conceal ""))

(strong
  "*" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))
