; Subscript with curly group - regex removed, Rust will filter via hash lookup
(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_) @sub_letter
    "}" @close_paren) @sub_object
  (#set! priority 101)
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_letter))

; Subscript direct - regex removed, Rust will filter via hash lookup
(subscript
  "_" @sub_symbol
  subscript: (_) @sub_object
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object))

; Superscript with curly group - regex removed, Rust will filter via hash lookup
(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (_) @sup_letter
    "}" @close_paren) @sup_object
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_letter))

; Superscript direct - regex removed, Rust will filter via hash lookup
(superscript
  "^" @sup_symbol
  superscript: (_) @sup_object
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object))
