; Typst script style conceals
; Superscript and subscript conceals
(attach
  (_)
  sup: (letter) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#set! priority 99)
  (#lua_func! @sup_object "sup"))

(attach
  (_)
  sup: (number) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#any-of? @sup_object "1" "2" "3" "4" "5" "6" "7" "8" "9")
  (#set! priority 99)
  (#lua_func! @sup_object "sup"))

(attach
  (_)
  sup: (ident) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#set! priority 99)
  (#lua_func! @sup_object "sup"))

(attach
  (_)
  "^" @sup_symbol
  sup: (number) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#any-of? @sup_object "1" "2" "3" "4" "5" "6" "7" "8" "9")
  (#set! priority 98)
  (#set! conceal "" @sup_symbol))

(attach
  (_)
  "^" @sup_symbol
  sup: (letter) @sup_object
  ((#match? @sup_object "[a-z]")
  (#has-ancestor? @sup_object math formula)
  (#set! priority 98)
  (#set! conceal "" @sup_object)))

; Subscript conceals
(attach
  (_)
  sub: (letter) @sub_object
  (#set! priority 99)
  (#lua_func! @sub_object "sub"))

(attach
  (_)
  sub: (number) @sub_object
  (#has-ancestor? @sub_object math formula)
  (#any-of? @sub_object "1" "2" "3" "4" "5" "6" "7" "8" "9")
  (#set! priority 99)
  (#lua_func! @sub_object "sub"))

(attach
  (_)
  sub: (ident) @sub_object
  (#has-ancestor? @sub_object math formula)
  (#set! priority 99)
  (#lua_func! @sub_object "sub"))

(attach
  (_)
  "_" @sub_symbol
  sub: (number) @sub_object
  (#any-of? @sub_object "1" "2" "3" "4" "5" "6" "7" "8" "9")
  (#has-ancestor? @sub_object math formula)
  (#set! priority 98)
  (#set! conceal "" @sub_symbol))

(attach
  (_)
  "_" @sub_symbol
  sub: (letter) @sub_object
  ((#match? @sub_object "[aehijklmnoprstuvx]")
  (#has-ancestor? @sub_object math formula)
  (#set! priority 98)
  (#set! conceal "" @sub_symbol)))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "cal" "frak" "mono" "sans" "bold")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

; Capture and conceal the opening parenthesis of the sub/supscript group
; For superscript with parentheses - hide both ^ and parentheses when content matches criteria
(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula
          (letter) @sup_letter)
        ")" @close_paren)
      (#match? @sup_letter "[a-z]")
      (#set! priority 97)
      (#lua_func! @sup_letter "sup"))))

(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula
          (letter) @sup_letter)
        ")" @close_paren)
      (#match? @sup_letter "[a-z]")
      (#set! priority 96)
      (#set! conceal "" @sup_symbol))))

; For superscript with parentheses - hide both ^ and parentheses when content is a number
(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula
          (number) @sup_number)
        ")" @close_paren)
      (#any-of? @sup_number "1" "2" "3" "4" "5" "6" "7" "8" "9")
      (#set! priority 97)
      (#lua_func! @sup_number "sup"))))

(math
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula
          (number) @sup_number)
        ")" @close_paren)
      (#any-of? @sup_number "1" "2" "3" "4" "5" "6" "7" "8" "9")
      (#set! priority 96)
      (#set! conceal "" @sup_symbol))))

(math
  (formula
    (attach
      (_)
      sup: (group
        "(" @_open_paren))
    (#set! conceal "" @_open_paren)))

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
        "(" @_open_paren)))
  (#set! conceal "" @_open_paren))

(math
  (formula
    (attach
      (_)
      sub: (group
        ")" @_close_paren)))
  (#set! conceal "" @_close_paren))
