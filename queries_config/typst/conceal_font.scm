; Typst font style conceals
; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name
    "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double" "upright")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#match? @font_letter "^[a-zA-Z]$")
  (#lua_func! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal ""))

; overline conceal for ident
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name "overline")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#match? @font_letter "^[a-zA-Z]+$")
  (#set-font! @font_letter @typ_font_name "font")
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
  (#set-conceal! @typ_math_font "conceal"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))
