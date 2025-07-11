; Typst math conceals
; Based on Typst math mode syntax tree structure

; Math function calls with special symbols
(call
  item: (ident) @func
  (#any-of? @func  "sqrt" "root" "sum" "product" "integral")
  ; (#has-ancestor? @func math formula)
  (#lua_func @conceal "conceal"))

(((ident) @conceal
  (#any-of? @conceal "sqrt" "root" "sum" "product" "integral"))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @conceal "conceal"))

; (((ident) @conceal_l
;   (#any-of? @conceal "paren.b" "brace.l" "brace.r" "brace.t" "brace.b" "bracket.l" "bracket.l.double" "bracket.r" "bracket.r.double" "bracket.t" "bracket.b" "turtle.l" "turtle.r" "turtle.t " "turtle.b" "bar.v"))
; ; (#has-ancestor? @conceal math formula)
; ; (#set! @conceal_l "m"))
; (#lua_func! @conceal_l "conceal"))


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
(symbol) @symbol
(#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
(#has-ancestor? @symbol math formula)
(#set! priority 90)
;
; ; Math delimiters
; (group
;   "(" @open
;   ")" @close
;   (#has-ancestor? @open math formula)
;   (#set! priority 95))
;
; (group
;   "[" @open
;   "]" @close
;   (#has-ancestor? @open math formula)
;   (#set! priority 95))
;
; (group
;   "{" @open
;   "}" @close
;   (#has-ancestor? @open math formula)
;   (#set! priority 95))
;
