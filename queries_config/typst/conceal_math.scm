; Typst math conceals
; Based on Typst math mode syntax tree structure

; Math function calls with special symbols
(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral")
  ; (#has-ancestor? @func math formula)
  (#lua_func! @typ_math_symbol "conceal"))

(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral"))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @typ_math_symbol "conceal"))

; Superscript and subscript handling
(attach
  sup: (_) @sup
  (#has-ancestor? @sup math formula)
  (#set! priority 110))

(attach
  sub: (_) @sub
  (#has-ancestor? @sub math formula)
  (#set! priority 110))

; Special symbols in math mode
((symbol) @symbol
(#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
(#has-ancestor? @symbol math formula)
(#set! priority 90))
