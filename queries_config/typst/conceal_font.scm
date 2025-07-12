; Typst font style conceals

; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula 
    (letter) @letter 
    (#lua_func! @letter @typ_font_name "font"))
  ")" @right_paren
  (#set! @right_paren conceal ""))

; (call
;   item: (ident) @func
;   (#eq? @func "italic")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Script/calligraphic symbols
; (call
;   item: (ident) @func
;   (#eq? @func "cal")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; (call
;   item: (ident) @func
;   (#eq? @func "script")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Blackboard bold symbols
; (call
;   item: (ident) @func
;   (#eq? @func "bb")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Sans-serif symbols
; (call
;   item: (ident) @func
;   (#eq? @func "sans")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Monospace symbols
; (call
;   item: (ident) @func
;   (#eq? @func "mono")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Fraktur symbols
; (call
;   item: (ident) @func
;   (#eq? @func "frak")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))
;
; ; Double-struck symbols
; (call
;   item: (ident) @func
;   (#eq? @func "double")
;   (#has-ancestor? @func math formula)
;   (#set! conceal ""))

; Math function calls with special symbols
(call
  item: (ident) @typ_math_font
  (#any-of? @typ_math_font "dif")
  ; (#has-ancestor? @func math formula)
  (#set! conceal ""))

(((ident) @typ_math_font
  (#any-of? @typ_math_font "dif"))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @typ_math_font "conceal"))
