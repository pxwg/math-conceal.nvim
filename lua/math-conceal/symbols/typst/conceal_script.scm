; Typst script style conceals
; Replace simple letter by italic symbols. Must before sub- superscript rulers!
((letter) @typ_math_symbol
  (#match? @typ_math_symbol "^[a-zA-Z]$")
  (#not-has-parent? @typ_math_symbol field call tagged)
  (#has-ancestor? @typ_math_symbol math)
  (#set-conceal! @typ_math_symbol "conceal"))

;conceal only singe `i`
((attach
  .
  (letter) @typ_symbol)
  (#any-of? @typ_symbol "i")
  (#set! @typ_symbol conceal "ⅈ"))

((formula
  .
  (letter) @typ_symbol .)
  (#any-of? @typ_symbol "i")
  (#set! @typ_symbol conceal "ⅈ"))

; Superscript and subscript conceals
; Conceal the opening parenthesis of the subscript group while the formula has no space
; A_(xxx) -> A_xxx
(attach
  (_)
  "^"
  sup: (group
    "(" @open_paren
    (formula
      .
      [
        (apply)
        (attach
          sup: (_) @sup_letter .)
        (attach
          sub: (_) .)
        (fac)
        (field)
        (group)
        (ident)
        (letter)
        (number)
        (root)
        (string)
        (symbol)
      ] .)
    ")" @close_paren) @sup_object
  (#match? @sup_object "^[(]\\S+[)]$")
  (#match? @sup_letter
    "^([0-9]|[a-pr-zABDEG-PRT-W]|[*+=()\\-]|alpha|beta|gamma|delta|epsilon|theta|iota|phi|chi|prime|prime.double|prime.triple|prime.quad|prime.rev|prime.rev.double|prime.rev.triple|prime.double.rev|prime.triple.rev|degree)$")
  (#has-ancestor? @sup_object math formula)
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(attach
  (_)
  "_"
  sub: (group
    "(" @open_paren
    (formula
      .
      [
        (apply)
        (attach
          sub: (_) @sub_letter .)
        (attach
          sup: (_) .)
        (fac)
        (field)
        (group)
        (ident)
        (letter)
        (number)
        (root)
        (string)
        (symbol)
      ] .)
    ")" @close_paren) @sub_object
  (#match? @sub_object "^[(]\\S+[)]$")
  (#match? @sub_letter "^([0-9]|[aehijklmnoprstuvx]|[+()=\\-]|beta|gamma|rho|phi|chi)$")
  (#has-ancestor? @sub_object math formula)
  (#set! @close_paren conceal "")
  (#set! @open_paren conceal ""))

; Sup conceal only limited call like:
; fonts
(attach
  (_)
  "^"
  sup: (group
    "(" @open_paren
    (formula
      .
      (call
        item: [
          (ident)
          (field)
        ] @typ_font_name) .)
    ")" @close_paren) @sup_object
  (#match? @sup_object "^[(]\\S+[)]$")
  (#any-of? @typ_font_name
    "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright" "acute" "acute.double"
    "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer" "dot" "dot.double"
    "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron" "overline" "tilde")
  (#not-has-parent? @typ_font_name field)
  (#has-ancestor? @sup_object math formula)
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

; Sub conceal only limited call like:
; fonts
(attach
  (_)
  "_"
  sub: (group
    "(" @open_paren
    (formula
      .
      (call
        item: [
          (ident)
          (field)
        ] @typ_font_name) .)
    ")" @close_paren) @sub_object
  (#match? @sub_object "^[(]\\S+[)]$")
  (#any-of? @typ_font_name
    "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright" "acute" "acute.double"
    "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer" "dot" "dot.double"
    "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron" "overline" "tilde")
  (#not-has-parent? @typ_font_name field)
  (#has-ancestor? @sub_object math formula)
  (#set! @close_paren conceal "")
  (#set! @open_paren conceal ""))

; A^a -> Aᵃ
(attach
  (_)
  "^" @sup_symbol
  sup: [
    (_) @sup_digit
    (_) @sup_letter
  ]
  (#has-ancestor? @sup_symbol math formula)
  (#match? @sup_digit "^([0-9]|[*+=()\\-])$")
  (#match? @sup_letter
    "^([a-pr-zABDEG-PRT-W]|alpha|beta|gamma|delta|epsilon|theta|iota|phi|chi|prime|prime.double|prime.triple|prime.quad|prime.rev|prime.rev.double|prime.rev.triple|prime.double.rev|prime.triple.rev|degree)$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_digit "sup")
  (#set-sup! @sup_letter "sup"))

; A^"a" -> Aᵃ
(attach
  (_)
  "^" @_sup_symbol
  sup: (string) @sup_string
  (#has-ancestor? @_sup_symbol math formula)
  (#match? @sup_string "^\"([0-9]|[*+=()\\-]|[a-pr-zABDEG-PRT-W])\"$")
  (#set! @_sup_symbol conceal "")
  (#set-sup! @sup_string "sup")
  (#set! priority 101))

; A_a -> Aₐ
(attach
  (_)
  "_" @sub_symbol
  sub: [
    (_) @sub_digit
    (_) @sub_letter
  ]
  (#has-ancestor? @sub_symbol math formula)
  (#match? @sub_digit "^([0-9]|[+()=\\-])$")
  (#match? @sub_letter "^([aehijklmnoprstuvx]|beta|gamma|rho|phi|chi)$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_digit "sub")
  (#set-sub! @sub_letter "sub"))

; A_"a" -> Aₐ
(attach
  (_)
  "_" @_sub_symbol
  sub: (string) @sub_string
  (#has-ancestor? @_sub_symbol math formula)
  (#match? @sub_string "^\"([0-9]|[+()=\\-]|[aehijklmnoprstuvx])\"$")
  (#set! @_sub_symbol conceal "")
  (#set-sub! @sub_string "sub")
  (#set! priority 101))

; A^(a) -> Aᵃ
(attach
  (_)
  "^" @sup_symbol
  sup: (group
    "(" @open_paren
    [
      (_) @sup_digit
      (_) @sup_letter
    ]
    ")" @close_paren) @content
  (#match? @sup_digit "^([0-9]|[*+=()\\-])$")
  (#match? @sup_letter
    "^([a-pr-zABDEG-PRT-W]|alpha|beta|gamma|delta|epsilon|theta|iota|phi|chi|prime|prime.double|prime.triple|prime.quad|prime.rev|prime.rev.double|prime.rev.triple|prime.double.rev|prime.triple.rev|degree)$")
  (#match? @content "^[(]\\S+[)]$")
  (#has-ancestor? @sup_symbol math formula)
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_digit "sup")
  (#set-sup! @sup_letter "sup"))

; A^("a") -> Aᵃ
(attach
  (_)
  "^" @_sup_symbol
  sup: (group
    "(" @_open_paren
    (formula
      (string) @sup_string .)
    ")" @_close_paren) @content
  (#match? @sup_string "^\"([0-9]|[*+=()\\-]|[a-pr-zABDEG-PRT-W])\"$")
  (#match? @content "^[(]\\S+[)]$")
  (#has-ancestor? @_sup_symbol math formula)
  (#set! @_open_paren conceal "")
  (#set! @_close_paren conceal "")
  (#set! @_sup_symbol conceal "")
  (#set-sup! @sup_string "sup")
  (#set! priority 101))

; A_(a) -> Aₐ
(attach
  (_)
  "_" @sub_symbol
  sub: (group
    "(" @open_paren
    [
      (_) @sub_digit
      (_) @sub_letter
    ]
    ")" @close_paren) @content
  (#match? @sub_digit "^([0-9]|[+()=\\-])$")
  (#match? @sub_letter "^([aehijklmnoprstuvx]|beta|gamma|rho|phi|chi)$")
  (#match? @content "^[(]\\S+[)]$")
  (#has-ancestor? @sub_symbol math formula)
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_digit "sub")
  (#set-sub! @sub_letter "sub"))

; A_("a") -> Aₐ
(attach
  (_)
  "_" @_sub_symbol
  sub: (group
    "(" @_open_paren
    (formula
      (string) @sub_string .)
    ")" @_close_paren) @content
  (#match? @sub_string "^\"([0-9]|[+()=\\-]|[aehijklmnoprstuvx])\"$")
  (#match? @content "^[(]\\S+[)]$")
  (#has-ancestor? @_sub_symbol math formula)
  (#set! @_open_paren conceal "")
  (#set! @_close_paren conceal "")
  (#set! @_sub_symbol conceal "")
  (#set-sub! @sub_string "sub")
  (#set! priority 101))
