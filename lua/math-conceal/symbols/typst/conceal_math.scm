((escape) @cmd_escape
  (#set-escape! @cmd_escape "typst"))

([
  (ident)
  (field)
] @typ_math_symbol
  (#not-has-parent? @typ_math_symbol field call tagged)
  (#has-ancestor? @typ_math_symbol math)
  (#set-conceal! @typ_math_symbol "conceal"))

(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "sqrt")
  (#has-ancestor? @typ_math_symbol math)
  (#set-conceal! @typ_math_symbol "conceal"))

(call
  item: (ident) @typ_math_symbol
  "("
  .
  (formula
    (number) @_number .)
  ")"
  (#eq? @typ_math_symbol "root")
  (#not-any-of? @_number "3" "4")
  (#has-ancestor? @typ_math_symbol math)
  (#set-conceal! @typ_math_symbol "conceal"))

(call
  item: (ident) @typ_math_symbol
  "("
  .
  (formula
    (number) @_number_3 .)
  ")"
  (#eq? @typ_math_symbol "root")
  (#eq? @_number_3 "3")
  (#has-ancestor? @typ_math_symbol math)
  (#set! @typ_math_symbol conceal "∛"))

(call
  item: (ident) @typ_math_symbol
  "("
  .
  (formula
    (number) @_number_4 .)
  ")"
  (#eq? @typ_math_symbol "root")
  (#eq? @_number_4 "4")
  (#has-ancestor? @typ_math_symbol math)
  (#set! @typ_math_symbol conceal "∜"))

([
  (ident)
  (field)
] @typ_symbol
  (#any-of? @typ_symbol
    "Im" "Re" "degree" "ell" "percent" "permille" "permyriad" "planck" "prime" "prime.double"
    "prime.double.rev" "prime.quad" "prime.rev" "prime.rev.double" "prime.rev.triple" "prime.triple"
    "prime.triple.rev" "angstrom")
  (#has-ancestor? @typ_symbol math)
  (#not-has-parent? @typ_symbol field call tagged)
  (#set-conceal! @typ_symbol "conceal"))

; #sym.<>
((code
  (field
    (_))) @typ_math_symbol
  (#match? @typ_math_symbol "^([#]sym[.])\\S+$")
  (#set-sym-conceal! @typ_math_symbol "conceal"))

([
  (ident)
  (field)
] @symbol
  (#any-of? @symbol
    "dot" "dot.basic" "dot.c" "dot.op" "dots" "dots.c" "dots.c.h" "dots.down" "dots.h" "dots.h.c"
    "dots.up" "dots.v")
  (#has-ancestor? @symbol math)
  (#not-has-parent? @symbol field call tagged)
  (#set-conceal! @symbol "conceal"))

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

; conceal brackets and comma in tables, grid etc. Also remove all comma in other commands
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
  (#not-has-parent? @typ_symbol field call tagged)
  (#has-ancestor? @typ_symbol math)
  (#set-conceal! @typ_symbol "conceal"))

; conceal command(content) -> (content)
(call
  item: (ident) @cmd
  "(" @left_brace
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "vec" "mat" "binom")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "(")
  (#set! @right_brace conceal ")"))

; conceal command(var1,var2) -> (var1 var2)
(call
  item: (ident) @cmd
  "," @punctuation.delimiter
  (#any-of? @cmd "vec" "mat" "binom")
  (#has-ancestor? @cmd math formula)
  (#set! @punctuation.delimiter conceal " "))

; conceal command(content) -> content
(call
  item: (ident) @cmd
  "(" @left_brace
  (_)
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "limits")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal ""))

((call
  item: (ident) @cmd
  "("
  .
  (formula
    (_) @symbol)
  ")")
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "limits")
  (#set-conceal! @symbol "conceal"))

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
; for simple expression frac(expression_1,expression_2)
; to (expression_1⧸expression_2)
; or for long_expression frac((long_expression_1),(long_expression_2))
; to (long_expression_1)∕(long_expression_2)
; Replace only first comma with division slash
; frac(content,content,style: str)
; use `⧸` BIG SOLIDUS U+29F8
(call
  item: (ident) @_frac_name
  "("
  .
  (_)
  .
  "," @punctuation.comma
  ")"
  (#eq? @_frac_name "frac")
  (#set! @punctuation.comma conceal "")
  (#set! @_frac_name conceal ""))

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
  ")" @right_paren
  (#set! @punctuation.comma conceal "∕")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @_frac_name conceal ""))

; Conceal style for allfunctions
; from cmd(content,content,style: str) to cmd(content,content)
(call
  item: (ident) @_func_name
  (#any-of? @_func_name "frac")
  "("
  "," @punctuation.comma
  .
  (tagged) @_tagged
  .
  ")"
  (#set! @punctuation.comma conceal "")
  (#set! @_tagged conceal ""))
