(call
  item: [
    (ident)
    (field)
  ] @typ_font_name
  (#any-of? @typ_font_name
    "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright" "acute" "acute.double"
    "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer" "dot" "dot.double"
    "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron" "overline" "tilde")
  (#has-ancestor? @typ_font_name math formula)
  (#set! conceal ""))

(call
  item: [
    (ident)
    (field)
  ] @typ_font_name
  "(" @left_paren
  (formula) @font_letter
  ")" @right_paren
  (#any-of? @typ_font_name
    "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright" "acute" "acute.double"
    "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer" "dot" "dot.double"
    "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron" "overline" "tilde")
  (#has-ancestor? @typ_font_name math formula)
  (#set! @typ_font_name conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set-font! @font_letter @typ_font_name))

; digits in font
(call
  item: [
    (ident)
    (field)
  ] @typ_font_name
  "(" @left_paren
  (formula) @font_digit
  ")" @right_paren
  (#any-of? @typ_font_name
    "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright" "acute" "acute.double"
    "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer" "dot" "dot.double"
    "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron" "overline" "tilde")
  (#has-ancestor? @typ_font_name math formula)
  (#lua-match? @font_digit "^%d+$")
  (#set! @left_paren conceal "")
  (#set! @typ_font_name conceal "")
  (#set! @right_paren conceal "")
  (#set-font! @font_digit @typ_font_name))

(call
  item: (ident) @typ_font_name
  "(" @open_paren
  ")" @close_paren
  (#any-of? @typ_font_name "scripts")
  (#has-ancestor? @typ_font_name math formula)
  (#set! @typ_font_name conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(attach
  (_)
  "^" @sup_symbol
  sup: (call
    item: (ident) @typ_font_name
    "(" @left_paren
    (formula
      (_) @typ_symbol)
    ")" @right_paren)
  (#any-of? @typ_font_name "scripts")
  (#has-ancestor? @typ_font_name math formula)
  (#set! @typ_font_name conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @sup_symbol conceal "")
  (#set-sup! @typ_symbol "sup"))
