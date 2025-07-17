; Typst font style conceals
; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name
    "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double" "upright" "overline")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula
    (letter) @font_letter
    (#lua_func! @font_letter @typ_font_name "font"))
  ")" @right_paren
  (#set! @right_paren conceal ""))

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

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))
