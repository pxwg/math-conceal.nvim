; Typst Greek letter conceals - regex removed, Rust hash table will filter
; Greek letters as function calls
(call
  item: (ident) @typ_greek_symbol
  (#set! priority 102)
  (#set-conceal! @typ_greek_symbol "conceal"))
  ; (#has-ancestor? @conceal math formula)

; (#lua_func! @conceal "conceal"))
; Greek letters as direct identifiers
((ident) @typ_greek_symbol
  (#set! priority 102)
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set-conceal! @typ_greek_symbol "conceal"))
