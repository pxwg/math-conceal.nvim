(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (text) @sub_object
    "}" @close_paren)
  (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_object))

(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (text) @sub_object
    "}" @close_paren)
  (#match? @sub_object "^[^[:space:]]*$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(subscript
  "_" @sub_symbol
  subscript: (letter) @sub_letter
  (#match? @sub_letter "^[aehijklmnoprstuvx1234567890]$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_letter))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (text) @sup_object
    "}" @close_paren)
  (#match? @sup_object "^[a-z1-9]$")
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_object))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (text) @sup_object
    "}" @close_paren)
  (#match? @sup_object "^[^[:space:]]*$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(superscript
  "^" @sup_symbol
  superscript: (letter) @sup_letter
  (#match? @sup_letter "^[a-z1-9]$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_letter))
