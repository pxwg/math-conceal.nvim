; conceal only in math
; fancy conceal any x^{a+b} or y_{c+d} to x^(a+b) or y_(c+d)
(subscript
  subscript: (curly_group
    [
      "{" @open_paren
      "}" @close_paren
    ]) @sub_object
  (#has-ancestor? @sub_object displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sub_object text_mode)
  (#set! @open_paren conceal "(")
  (#set! @close_paren conceal ")"))

(superscript
  superscript: (curly_group
    [
      "{" @open_paren
      "}" @close_paren
    ]) @sup_object
  (#has-ancestor? @sup_object displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sup_object text_mode)
  (#set! @open_paren conceal "(")
  (#set! @close_paren conceal ")"))

; do not conceal symbols after uderscore in textmode \label{LABEL_WITH_2NUMBER}
;                                                                 this ^
(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_) @sub_letter
    "}" @close_paren) @sub_object
  (#match? @sub_object "^\\{[aehijklmnoprstuvx1234567890]\\}$")
  (#has-ancestor? @sub_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sub_symbol text_mode)
  (#set! priority 101)
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_letter))

(subscript
  "_" @sub_symbol
  subscript: (_) @sub_object
  (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
  (#has-ancestor? @sub_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sub_symbol text_mode)
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (_) @sup_letter
    "}" @close_paren) @sup_object
  (#has-ancestor? @sup_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sup_symbol text_mode)
  (#match? @sup_object "^\\{[a-z0-9]\\}$")
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_letter))

(superscript
  "^" @sup_symbol
  superscript: (_) @sup_object
  (#has-ancestor? @sup_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sup_symbol text_mode)
  (#match? @sup_object "^[a-z0-9]$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object))

; conceal when simple command, text mode(`\text` command)  or word(one or more letters)
; do not conceal if inner \frac{a}{b} that make wrong a_a/b or a^a/b with simple expression
; Complex expression in sub- or superscript is very rare
; Thats why a^((1+a2+b)) or a_((1+a2+b)) are allowable
(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    .
    (generic_command
      (command_name) @_frac_name)
    .
    (text
      word: [
        (subscript
          subscript: (letter) @sub_letter)
        (superscript
          superscript: (letter) @sup_letter)
      ] .)?
    .
    "}" @close_paren)
  (#has-ancestor? @sup_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sup_symbol text_mode)
  (#not-match? @_frac_name "^\\\\[dtc]?frac$")
  (#match? @sup_letter "^[a-z0-9]$")
  (#match? @sub_letter "^[aehijklmnoprstuvx1234567890]$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    .
    [
      (text
        .
        word: (word) @first_letter
        .
        word: [
          (subscript
            subscript: (letter) @sub_letter)
          (superscript
            superscript: (letter) @sup_letter)
        ] .)
      ((text_mode)
        .
        (text
          word: [
            (subscript
              subscript: (letter) @sub_letter)
            (superscript
              superscript: (letter) @sup_letter)
          ] .) .)
      (text
        .
        word: (word) @first_letter .)
      (text_mode)
    ]
    .
    "}" @close_paren)
  (#has-ancestor? @sup_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sup_symbol text_mode)
  (#match? @first_letter "^[a-zA-Z0-9]$")
  (#match? @sup_letter "^[a-z0-9]$")
  (#match? @sub_letter "^[aehijklmnoprstuvx1234567890]$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    .
    (generic_command
      (command_name) @_frac_name)
    .
    (text
      word: [
        (subscript
          subscript: (letter) @sub_letter)
        (superscript
          superscript: (letter) @sup_letter)
      ] .)?
    .
    "}" @close_paren)
  (#has-ancestor? @sub_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sub_symbol text_mode)
  (#not-match? @_frac_name "^\\\\[dtc]?frac$")
  (#match? @sup_letter "^[a-z0-9]$")
  (#match? @sub_letter "^[aehijklmnoprstuvx1234567890]$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    .
    [
      (text
        .
        word: (word) @first_letter
        .
        word: [
          (subscript
            subscript: (letter) @sub_letter)
          (superscript
            superscript: (letter) @sup_letter)
        ] .)
      ((text_mode)
        .
        (text
          word: [
            (subscript
              subscript: (letter) @sub_letter)
            (superscript
              superscript: (letter) @sup_letter)
          ] .) .)
      (text
        .
        word: (word) @first_letter .)
      (text_mode)
    ]
    .
    "}" @close_paren)
  (#has-ancestor? @sub_symbol displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @sub_symbol text_mode)
  (#match? @first_letter "^[a-zA-Z0-9]$")
  (#match? @sup_letter "^[a-z0-9]$")
  (#match? @sub_letter "^[aehijklmnoprstuvx1234567890]$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))
