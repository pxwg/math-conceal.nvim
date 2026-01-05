; Typst delimiter conceals
; Math delimiters - parentheses, brackets, braces
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "lr" "left" "right")
  (#has-ancestor? @typ_math_delim math formula)
  (#set! conceal ""))

; Norm delimiters
((call
        item: (ident) @cmd
        "(" @left_brace
        (_)
        ")" @right_brace)
 (#eq? @cmd "norm")
 (#set! @cmd conceal "")
 (#set! @left_brace conceal "‖")
 (#set! @right_brace conceal "‖"))


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

((align "&" @typ_inline_ampersand)
  (#set! @typ_inline_ampersand conceal ""))
