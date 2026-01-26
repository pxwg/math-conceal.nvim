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

; Escape sequences - regex removed, Rust will filter
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
  item: (ident) @_func_name
  (#eq? @_func_name "frac")
  (_)
  "," @punctuation.comma
  (_))
  (#set! conceal "/")
  (#set! priority 105))

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

; Math operators and symbols - regex removed, Rust will filter
((ident) @typ_math_symbol
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set! priority 101)
  (#set-conceal! @typ_math_symbol "conceal"))

; Math operators and symbols with modifiers - regex removed, Rust will filter
((field) @typ_math_symbol
  (#set! priority 103)
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set-conceal! @typ_math_symbol "conceal"))
