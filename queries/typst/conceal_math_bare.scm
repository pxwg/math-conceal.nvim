; Typst math conceals
; Based on Typst math mode syntax tree structure
; Math function calls with special symbols
(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral" "sqrt")
  ; (#has-ancestor? @func math formula)
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral"))
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

((escape) @typ_math_symbol
  (#set! priority 102)
  (#set-escape! @typ_math_symbol "conceal"))

; Special symbols in math mode
((symbol) @symbol
  (#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
  (#has-ancestor? @symbol math formula)
  (#set! priority 90))

; Conceal "frac" and replace with opening parenthesis
((call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac"))
  (#set! conceal "" @_frac_name)
  (#set! priority 1000))

; Replace comma with division slash
((call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac")
  (_)
  .
  "," @_comma
  (_))
  (#set! conceal "/" @_comma))

; Conceal "abs" function name
(call
  item: (ident) @abs_name
  (#eq? @abs_name "abs")
  (#set! conceal "")
  (#set! priority 100))

; Conceal parentheses for abs function
(call
  item: (ident) @func_name
  "(" @left_paren
  (_)
  ")" @right_paren
  (#eq? @func_name "abs")
  (#set! conceal "|" @left_paren)
  (#set! conceal "|" @right_paren)
  (#set! priority 90))
