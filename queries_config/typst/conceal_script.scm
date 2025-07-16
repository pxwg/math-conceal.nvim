; Typst script style conceals
; Superscript and subscript conceals
(attach
  sup: (letter) @sup_letter
  (#has-ancestor? @sup_letter math formula)
  (#set! priority 110)
  (#lua_func! @sup_letter "sup"))

(attach
  sup: (number) @sup_number
  (#has-ancestor? @sup_number math formula)
  (#set! priority 110)
  (#lua_func! @sup_number "sup"))

(attach
  sup: (ident) @sup_ident
  (#has-ancestor? @sup_ident math formula)
  (#set! priority 110)
  (#lua_func! @sup_ident "sup"))

(attach
  sub: (letter) @sub_letter
  (#has-ancestor? @sub_letter math formula)
  (#set! priority 110)
  (#lua_func! @sub_letter "sub"))

(attach
  sub: (number) @sub_number
  (#has-ancestor? @sub_number math formula)
  (#set! priority 110)
  (#lua_func! @sub_number "sub"))

(attach
  sub: (ident) @sub_ident
  (#has-ancestor? @sub_ident math formula)
  (#set! priority 110)
  (#lua_func! @sub_ident "sub"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "cal" "frak" "mono" "sans" "bold")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

; Capture and conceal the opening parenthesis of the sub/supscript group
(math
  (formula
    (attach
      (_)
      sup: (group
        "(" @_open_paren)))
  (#set! conceal "" @_open_paren))

(math
  (formula
    (attach
      (_)
      sub: (group
        "(" @_open_paren)))
  (#set! conceal "" @_open_paren))

(math
  (formula
    (attach
      (_)
      sup: (group
        ")" @_close_paren)))
  (#set! conceal "" @_close_paren))

(math
  (formula
    (attach
      (_)
      sub: (group
        ")" @_close_paren)))
  (#set! conceal "" @_close_paren))
