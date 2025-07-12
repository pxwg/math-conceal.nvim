; Typst script style conceals

; Superscript and subscript conceals
(attach
  sup: (letter) @sup_letter
  (#has-ancestor? @sup_letter math formula)
  (#lua_func! @sup_letter "conceal"))

(attach
  sup: (number) @sup_number
  (#has-ancestor? @sup_number math formula)
  (#lua_func! @sup_number "conceal"))

(attach
  sup: (ident) @sup_ident
  (#has-ancestor? @sup_ident math formula)
  (#lua_func! @sup_ident "conceal"))

(attach
  sub: (letter) @sub_letter
  (#has-ancestor? @sub_letter math formula)
  (#lua_func! @sub_letter "conceal"))

(attach
  sub: (number) @sub_number
  (#has-ancestor? @sub_number math formula)
  (#lua_func! @sub_number "conceal"))

(attach
  sub: (ident) @sub_ident
  (#has-ancestor? @sub_ident math formula)
  (#lua_func! @sub_ident "conceal"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "cal" "frak" "mono" "sans" "bold")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

