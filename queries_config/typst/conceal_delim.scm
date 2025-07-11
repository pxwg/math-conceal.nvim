; Typst delimiter conceals

; Math delimiters - parentheses, brackets, braces
(call
  item: (ident) @func
  (#any-of? @func "lr" "left" "right")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

; Angle brackets
(call
  item: (ident) @func
  (#any-of? @func "angle" "langle" "rangle")
  (#has-ancestor? @func math formula)
  (#lua_func! @func "conceal"))

; Floor and ceiling
(call
  item: (ident) @func
  (#any-of? @func "floor" "ceil" "lfloor" "rfloor" "lceil" "rceil")
  (#has-ancestor? @func math formula)
  (#lua_func! @func "conceal"))

; Norm delimiters
(call
  item: (ident) @func
  (#any-of? @func "norm" "abs")
  (#has-ancestor? @func math formula)
  (#lua_func! @func "conceal"))

; Vertical bars and double bars
(symbol) @delim
(#any-of? @delim "|" "||")
(#has-ancestor? @delim math formula)
(#lua_func! @delim "conceal")

; ; Group delimiters in math mode
; (group
;   "{" @open_brace
;   (#has-ancestor? @open_brace math formula)
;   (#set! conceal ""))
;
; (group
;   "}" @close_brace
;   (#has-ancestor? @close_brace math formula)
;   (#set! conceal ""))

; (call
;   "(" @open_paren
;   (#has-ancestor? @open_paren math formula)
;   ; (#not-has-ancestor? @open_paren group)
;   (#set! conceal ""))
;
;
; (call
;   ")" @close_paren
;   (#has-ancestor? @close_paren math formula)
;   ; (#not-has-ancestor? @close_paren group)
;   (#set! conceal ""))

(math
  "$" @inline_dollar
  ; (#has-ancestor? @inline_dollar math formula)
  (#set! conceal ""))

; (group
;   "[" @open_bracket
;   (#has-ancestor? @open_bracket math formula)
;   (#set! conceal ""))
;
; (group
;   "]" @close_bracket
;   (#has-ancestor? @close_bracket math formula)
;   (#set! conceal ""))
;
