([
  (ident)
  (field)
] @typ_greek_symbol
  (#has-ancestor? @typ_greek_symbol math)
  (#not-has-parent? @typ_greek_symbol field call)
  (#set-greek! @typ_greek_symbol "greek"))

(call
  item: [
    (ident)
    (field)
  ] @typ_greek_symbol
  (#has-ancestor? @typ_greek_symbol math)
  (#set-greek! @typ_greek_symbol "greek"))

(call
  item: [
    (ident)
    (field)
  ] @typ_font_name
  "(" @left_paren
  (formula) @typ_greek_symbol
  ")" @right_paren
  (#any-of? @typ_font_name "bb" "bold" "cal" "frak" "italic" "mono" "sans" "scr" "serif" "upright")
  (#has-ancestor? @typ_font_name math formula)
  (#not-has-parent? @typ_font_name field)
  (#set! @typ_font_name conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set-greek_font! @typ_greek_symbol @typ_font_name))

(call
  item: [
    (ident)
    (field)
  ] @typ_font_name
  "(" @left_paren
  (formula) @typ_greek_symbol
  ")" @right_paren
  (#any-of? @typ_font_name
    "acute" "acute.double" "arrow" "arrow.l" "arrow.l.r" "breve" "caron" "circle" "dash" "diaer"
    "dot" "dot.double" "dot.quad" "dot.triple" "grave" "harpoon" "harpoon.lt" "hat" "macron"
    "overline" "tilde")
  (#has-ancestor? @typ_font_name math formula)
  (#not-has-parent? @typ_font_name field)
  (#set! @typ_font_name conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set-greek_font! @typ_greek_symbol @typ_font_name))
