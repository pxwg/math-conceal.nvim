; Typst script style conceals
; Superscript and subscript conceals
; A_a -> A(concealed sub:a) - regex removed, Rust will filter
(attach
  (_)
  "^" @sup_symbol
  sup: (_) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#set! priority 98)
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object "sup"))

; Subscript conceals - regex removed, Rust will filter
(attach
  (_)
  "_" @sub_symbol
  sub: (_) @sub_object
  (#has-ancestor? @sub_object math formula)
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object "sub"))

; Capture and conceal the opening parenthesis of the sub/supscript group
; For superscript with parentheses - regex removed, Rust will filter
; Concealed symbol with lua_func: concealing the subscript and superscript symbols
; A_(a) -> A(concealed sub:a)
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula) @sup_letter
        ")" @close_paren)
      (#has-ancestor? @sup_letter math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")
      (#set! @sup_symbol conceal "")
      (#set-sup! @sup_letter)))

  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (formula) @sub_object
        ")" @close_paren)
      (#has-ancestor? @sub_object math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")
      (#set! @sub_symbol conceal "")
      (#set-sub! @sub_object)))

; Conceal the opening parenthesis of the subscript group while the formula has no space
; A_(xxx) -> A_xxx - regex removed, Rust will filter
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (_) @sup_object
        ")" @close_paren)
      (#has-ancestor? @sup_object math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")))

  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (_) @sub_object
        ")" @close_paren)
      (#has-ancestor? @sub_object math formula)
      (#set! @close_paren conceal "")
      (#set! @open_paren conceal "")))
