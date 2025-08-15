(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_) @sub_letter
    "}" @close_paren) @sub_object
  (#match? @sub_object "^\\{[aehijklmnoprstuvx1234567890]\\}$")
  (#set! priority 101)
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_letter))

(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_)
    "}" @close_paren) @sub_object
  (#match? @sub_object "^\\{\\\\\\S+\\}")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(subscript
  "_" @sub_symbol
  subscript: (_) @sub_object
  (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (_) @sup_letter
    "}" @close_paren) @sup_object
  (#match? @sup_object "^\\{[a-z1-9]\\}$")
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_letter))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    "}" @close_paren) @sup_object
  (#match? @sup_object "^\\{\\\\\\S+\\}$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(superscript
  "^" @sup_symbol
  superscript: (_) @sup_object
  (#match? @sup_object "^[a-z1-9]$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object))
