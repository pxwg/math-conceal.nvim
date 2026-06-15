((escape) @cmd_escape
  (#set-escape! @cmd_escape "typst"))

([
  (ident)
  (field)
] @typ_math_symbol
  (#not-has-parent? @typ_math_symbol field call)
  (#has-ancestor? @typ_math_symbol math)
  (#set-conceal! @typ_math_symbol "conceal"))

; #sym.<>
((code
  (field
    (_))) @typ_math_symbol
  (#match? @typ_math_symbol "^([#]sym[.])\\S+$")
  (#set-sym-conceal! @typ_math_symbol "conceal"))

((shorthand) @symbol
  (#has-ancestor? @symbol math)
  (#set-conceal! @symbol "conceal"))

((shorthand) @typ_symbol
  (#any-of? @typ_symbol "..." "--" "---" "-?" "~")
  (#not-has-ancestor? @typ_symbol math)
  (#set-conceal! @typ_symbol "conceal"))

((symbol) @typ_symbol
  (#any-of? @typ_symbol "'")
  (#has-ancestor? @typ_symbol math)
  (#set-conceal! @typ_symbol "conceal"))

; conceal brackets and comma in tables, grid etc.
([
  "," @punctuation.delimiter
  (content
    "[" @left_1
    "]" @right_1)
] @content
  (#has-ancestor? @content call)
  (#has-parent? @content group)
  (#set! @punctuation.delimiter conceal " ")
  (#set! @left_1 conceal "")
  (#set! @right_1 conceal ""))

([
  (ident)
  (field)
] @typ_symbol
  (#any-of? @typ_symbol "dif" "partial")
  (#not-has-parent? @typ_symbol field call)
  (#has-ancestor? @typ_symbol math)
  (#set-conceal! @typ_symbol "conceal"))

(call
  item: (ident) @cmd
  "(" @left_brace
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "vec")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "(")
  (#set! @right_brace conceal ")"))

(call
  item: (ident) @typ_symbol
  "(" @left_paren
  (_)
  ")" @right_paren
  (#any-of? @typ_symbol "dif")
  (#has-ancestor? @typ_symbol math formula)
  (#set! @typ_symbol conceal "𝚍"))

(fraction
  "/" @frac
  (#set! @frac conceal "∕"))

; Conceal "frac" and replace with opening parenthesis
; only for simple expression frac(expression_1,expression_2)
; to expression_1/expression_2
; or for long_expression frac((long_expression_1),(long_expression_2))
; to (long_expression_1)/(long_expression_2)
; Replace only first comma with division slash
; frac(content,content,style: str)
; use `⧸` BIG SOLIDUS U+29F8
(call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac")
  "(" @left_paren
  .
  [
    (formula
      .
      (letter) .)
    (formula
      .
      (number) .)
    (formula
      .
      (attach) .)
    (formula
      .
      (group) .)
  ]
  .
  "," @punctuation.comma
  .
  [
    (formula
      .
      (letter) .)
    (formula
      .
      (number) .)
    (formula
      .
      (attach) .)
    (formula
      .
      (group) .)
  ]
  .
  (","
    .
    (tagged))?
  ")" @right_paren
  (#set! @punctuation.comma conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @_frac_name conceal ""))

; Conceal style for all frac functions
; from frac(content,content,style: str) to frac(content,content)
(call
  item: (ident) @_func_name
  (#eq? @_func_name "frac")
  (_)
  .
  ","
  .
  (_)
  .
  "," @punctuation.comma
  .
  (tagged) @_tagged
  (#set! @punctuation.comma conceal "")
  (#set! @_tagged conceal ""))
