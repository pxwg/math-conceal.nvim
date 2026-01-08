; Typst font style conceals - regex removed, Rust will filter
; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name
    "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double" "upright" )
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal ""))

; overline conceal for ident - regex removed, Rust will filter
(call
  item: (_) @typ_font_name
  (#any-of? @typ_font_name "overline" "tilde" "hat" "dot" "dot.double")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal "")
  (#set! priority 102))

(call
  item: (_) @typ_font_name
  (#any-of? @typ_font_name "overline")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal "")
  (#set! priority 102))

; Math function calls with special symbols
(call
  item: (ident) @typ_math_font
  (#any-of? @typ_math_font "dif")
  ; (#has-ancestor? @func math formula)
  (#set! conceal "d"))

(((ident) @typ_math_font
  (#any-of? @typ_math_font "dif"))
  ; (#has-ancestor? @conceal math formula)
  (#set! @typ_math_font "d"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))
