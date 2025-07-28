; Typst script style conceals
; Superscript and subscript conceals
; A_a -> A(concealed sub:a)
(attach
  (_)
  "^" @sup_symbol
  sup: (_) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#match? @sup_object "^[1-9a-z]$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object "sup"))

; Subscript conceals
(attach
  (_)
  "_" @sub_symbol
  sub: (_) @sub_object
  (#has-ancestor? @sub_object math formula)
  (#match? @sub_object "^[1-9aehijklmnoprstuvx]$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object "sub"))

; Capture and conceal the opening parenthesis of the sub/supscript group
; For superscript with parentheses - hide both ^ and parentheses when content matches criteria
; Concealed symbol with lua_func: concealing the subscript and superscript symbols
; A_(a) -> A(concealed sub:a)
(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula) @sup_letter
        ")" @close_paren)
      (#match? @sup_letter "^[a-z1-9]$")
      (#set! @sup_symbol conceal "")
      (#set-sup! @sup_letter))))

(math
  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (formula) @sub_object
        ")" @close_paren)
      (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
      (#set! @sub_symbol conceal "")
      (#set-sub! @sub_object))))

; Conceal the opening parenthesis of the subscript group while the formula has no space
; A_(xxx) -> A_xxx
(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula) @sup_number
        ")" @close_paren)
      (#not-match? @sup_number ".* .*")
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal ""))))

(math
  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (formula) @sub_number
        ")" @close_paren)
      (#not-match? @sub_number ".* .*")
      (#set! @close_paren conceal "")
      (#set! @open_paren conceal ""))))
