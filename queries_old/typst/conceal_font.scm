; Math function calls with special symbols
(call
  item: (ident) @typ_math_font
  (#any-of? @typ_math_font "dif")
  ; (#has-ancestor? @func math formula)
  (#set! conceal ""))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))
