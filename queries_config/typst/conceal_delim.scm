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
  (#lua_func! @typ_math_delim "conceal"))

; Floor and ceiling
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "floor" "ceil" "lfloor" "rfloor" "lceil" "rceil")
  (#has-ancestor? @typ_math_delim math formula)
  (#lua_func! @typ_math_delim "conceal"))

; Norm delimiters
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "norm")
  (#has-ancestor? @typ_math_delim math formula)
  (#lua_func! @typ_math_delim "conceal"))

; Vertical bars and double bars
((symbol) @typ_math_delim
(#any-of? @typ_math_delim "|" "||")
(#has-ancestor? @typ_math_delim math formula)
(#lua_func! @typ_math_delim "conceal"))

(math
  "$" @typ_inline_dollar
  (#set! conceal ""))
