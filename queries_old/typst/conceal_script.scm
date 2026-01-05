
; Conceal the opening parenthesis of the subscript group while the formula has no space
; A_(xxx) -> A_xxx
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (_) @sup_object
        ")" @close_paren)
      (#match? @sup_object "^[A-Za-z0-9]+$")
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
      (#match? @sub_object "^[A-Za-z1-9]+$")
      (#has-ancestor? @sub_object math formula)
      (#set! @close_paren conceal "")
      (#set! @open_paren conceal "")))
