; https://www.typst.app/universe/package/physica
; Physics constants, symbols, units and quantities
([
  (ident)
  (field)
] @typ_phy_symbol
  (#any-of? @typ_phy_symbol "cprod" "dprod" "grad" "hbar")
  (#has-ancestor? @typ_phy_symbol math)
  (#not-has-parent? @typ_phy_symbol field call tagged)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Symbols
(call
  item: (ident) @typ_phy_symbol
  (#any-of? @typ_phy_symbol "Order")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "𝒪︀"))

(call
  item: (ident) @typ_phy_symbol
  (#any-of? @typ_phy_symbol "order")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "ℴ︀"))

(call
  item: (ident) @cmd
  [
    ";" @comma
    "(" @left_brace
    ")" @right_brace
  ]
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "Set")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "{")
  (#set! @comma conceal "￨")
  (#set! @right_brace conceal "}"))

(call
  item: (ident) @cmd
  [
    "(" @left_brace
    ")" @right_brace
  ]
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "evaluated")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal "￨"))

; "(" "[" "{" "|" "||"
(call
  item: (ident) @cmd
  "(" @left_brace
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd
    "admat" "dmat" "grammat" "hmat" "imat" "jmat" "rot2mat" "rot3xmat" "rot3ymat" "rot3zmat"
    "vecrow" "xmat" "zmat")
  (#set! @left_brace conceal "(")
  (#set! @right_brace conceal ")"))

(call
  item: (ident) @cmd
  "(" @left_brace
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (string) @_delim)) @_conceal
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd
    "admat" "dmat" "hmat" "jmat" "grammat" "imat" "zmat" "xmat" "rot2mat" "rot3xmat" "rot3ymat"
    "rot3zmat" "vecrow")
  (#eq? @_delim "\"(\"")
  (#set! @_conceal conceal "")
  (#set! @left_brace conceal "(")
  (#set! @right_brace conceal ")"))

(call
  item: (ident) @cmd
  "(" @left_brace
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (string) @_delim)) @_conceal
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd
    "admat" "dmat" "grammat" "hmat" "jmat" "imat" "zmat" "xmat" "rot2mat" "rot3xmat" "rot3ymat"
    "rot3zmat" "vecrow")
  (#eq? @_delim "\"[\"")
  (#set! @_conceal conceal "")
  (#set! @left_brace conceal "[")
  (#set! @right_brace conceal "]"))

(call
  item: (ident) @cmd
  "(" @left_brace
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (string) @_delim)) @_conceal
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd
    "admat" "dmat" "grammat" "hmat" "jmat" "imat" "zmat" "xmat" "rot2mat" "rot3xmat" "rot3ymat"
    "rot3zmat" "vecrow")
  (#eq? @_delim "\"{\"")
  (#set! @_conceal conceal "")
  (#set! @left_brace conceal "{")
  (#set! @right_brace conceal "}"))

(call
  item: (ident) @cmd
  "(" @left_brace
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (string) @_delim)) @_conceal
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd
    "admat" "dmat" "hmat" "jmat" "grammat" "imat" "rot2mat" "rot3xmat" "rot3ymat" "rot3zmat"
    "vecrow" "xmat" "zmat")
  (#eq? @_delim "\"|\"")
  (#set! @_conceal conceal "")
  (#set! @left_brace conceal "￨")
  (#set! @right_brace conceal "￨"))

(call
  item: (ident) @cmd
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (code
        (bool)))) @_conceal
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "hmat" "grammat" "jmat" "dd")
  (#set! @_conceal conceal ""))

(call
  item: (ident) @cmd
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    field: (ident) @_ident) @_conceal
  (#any-of? @_ident "s" "style")
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "dv" "pdv")
  (#set! @_conceal conceal ""))

(call
  item: (ident) @cmd
  "(" @left_brace
  [
    ","
    ";"
  ] @_conceal
  .
  (tagged
    (formula
      (string) @_delim)) @_conceal
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "vecrow")
  (#eq? @_delim "\"||\"")
  (#set! @_conceal conceal "")
  (#set! @left_brace conceal "║")
  (#set! @right_brace conceal "║"))

(call
  item: (ident) @cmd
  "(" @open_paren
  (formula
    (_) .)
  ")" @close_paren
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "vb")
  (#set! @cmd conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(call
  item: (ident) @cmd
  "(" @open_paren
  (formula
    (_) .)
  ")" @close_paren
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "vu")
  (#set! @cmd conceal "")
  (#set! @open_paren conceal "̂")
  (#set! @close_paren conceal ""))

(call
  item: (ident) @cmd
  "(" @open_paren
  (formula
    (_) .)
  ")" @close_paren
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "va")
  (#set! @cmd conceal "")
  (#set! @open_paren conceal "⃗")
  (#set! @close_paren conceal ""))

; conceal command(content) -> (content)
(call
  item: (ident) @cmd
  "(" @left_brace
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "mdet")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "￨")
  (#set! @right_brace conceal "￨"))

; conceal command(var1,var2) -> (var1 var2)
(call
  item: (ident) @cmd
  "," @punctuation.delimiter
  (#any-of? @cmd
    "admat" "dd" "difference" "dmat" "dv" "grammat" "hmat" "imat" "jmat" "mdet" "pdv" "rot2mat"
    "rot3xmat" "rot3ymat" "rot3zmat" "var" "xmat" "zmat")
  (#has-ancestor? @cmd math formula)
  (#set! @punctuation.delimiter conceal " "))

(call
  item: (ident) @typ_phy_symbol
  (#has-ancestor? @typ_phy_symbol math formula)
  (#any-of? @typ_phy_symbol
    "admat" "dmat" "grammat" "hmat" "imat" "jmat" "mdet" "zmat" "rot2mat" "rot3xmat" "rot3ymat"
    "rot3zmat" "vecrow" "xmat")
  (#set-conceal! @typ_phy_symbol "conceal"))

((call
  item: (ident) @cmd
  "(" @left_brace
  (formula)
  ")" @right_brace)
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "expval" "iprod")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "⟩"))

(attach
  (_)
  "^" @sup_symbol
  sup: (_) @typ_phy_symbol
  (#has-ancestor? @sup_symbol math formula)
  (#any-of? @typ_phy_symbol "dagger" "TT")
  (#set! @sup_symbol conceal "")
  (#set-sup! @typ_phy_symbol "sup"))

(call
  item: (ident) @typ_phy_symbol
  "("
  (_)
  ")"
  (#any-of? @typ_phy_symbol "dd" "dv" "difference" "pdv" "var")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set-conceal! @typ_phy_symbol "conceal"))

(call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula
    (_) @content .)
  .
  ")" @right_paren
  (#any-of? @typ_phy_symbol "dd" "dv" "difference" "var")
  (#match? @content "^\\S$")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set-conceal! @typ_phy_symbol "conceal"))

; dd(f,x) -> 𝚍f𝚍x
((call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula
    (_) @left_content .)
  .
  "," @punctuation.comma
  .
  (formula
    (_) @right_content .)
  .
  ")" @right_paren)
  (#has-ancestor? @typ_phy_symbol math formula)
  (#any-of? @typ_phy_symbol "dd")
  (#match? @left_content "^\\S$")
  (#match? @right_content "^\\S$")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @typ_phy_symbol conceal "𝚍")
  (#set! @punctuation.comma conceal "𝚍"))

((call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula
    (_) @left_content .)
  .
  "," @punctuation.comma
  .
  (formula
    (_) @right_content .)
  .
  ")" @right_paren)
  (#has-ancestor? @typ_phy_symbol math formula)
  (#any-of? @typ_phy_symbol "difference")
  (#match? @left_content "^\\S$")
  (#match? @right_content "^\\S$")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @typ_phy_symbol conceal "Δ")
  (#set! @punctuation.comma conceal "Δ"))

((call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula
    (_) @left_content .)
  .
  "," @punctuation.comma
  .
  (formula
    (_) @right_content .)
  .
  ")" @right_paren)
  (#has-ancestor? @typ_phy_symbol math formula)
  (#any-of? @typ_phy_symbol "var")
  (#match? @left_content "^\\S$")
  (#match? @right_content "^\\S$")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @typ_phy_symbol conceal "Δ")
  (#set! @punctuation.comma conceal "Δ"))

; dv(f,x) -> 𝚍(fx)
((call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula)
  .
  "," @punctuation.comma
  .
  (formula)
  .
  ")" @right_paren)
  (#has-ancestor? @typ_phy_symbol math formula)
  (#eq? @typ_phy_symbol "dv")
  (#set! @typ_phy_symbol conceal "dͮ")
  (#set! @punctuation.comma conceal ""))

; pdv(f,x) -> ∂(fx)
((call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  .
  (formula)
  .
  "," @punctuation.comma
  .
  (formula)
  .
  ")" @right_paren)
  (#has-ancestor? @typ_phy_symbol math formula)
  (#eq? @typ_phy_symbol "pdv")
  (#set! @typ_phy_symbol conceal "∂")
  (#set! @punctuation.comma conceal ""))

(call
  item: (ident) @typ_phy_symbol
  "(" @left_paren
  (_)
  ")" @right_paren
  (#any-of? @typ_phy_symbol "grad")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "𝛁"))

(call
  item: (ident) @typ_phy_symbol
  "(" @symbol
  (_)
  ")" @right_paren
  (#any-of? @typ_phy_symbol "div")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "𝛁")
  (#set! @symbol conceal "·")
  (#set! @right_paren conceal ""))

(call
  item: (ident) @typ_phy_symbol
  "(" @symbol
  (_)
  ")" @right_paren
  (#any-of? @typ_phy_symbol "curl")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "𝛁")
  (#set! @symbol conceal "×")
  (#set! @right_paren conceal ""))

(call
  item: (ident) @typ_phy_symbol
  "(" @sup_letter
  (_)
  ")" @right_paren
  (#any-of? @typ_phy_symbol "laplacian")
  (#has-ancestor? @typ_phy_symbol math formula)
  (#set! @typ_phy_symbol conceal "𝛁")
  (#set! @sup_letter conceal "²")
  (#set! @right_paren conceal ""))

(call
  item: (ident) @func
  "(" @left_paren
  (_)
  ")" @right_paren
  (#any-of? @func "op")
  (#has-ancestor? @func math formula)
  (#set! @func conceal "")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal ""))

((call
  item: (ident) @cmd
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @cmd "bra")
  (#has-ancestor? @cmd math formula)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "￨"))

((call
  item: (ident) @cmd
  "(" @left_brace
  (_)
  ")" @right_brace)
  (#eq? @cmd "ket")
  (#set! @cmd conceal "")
  (#set! @right_brace conceal "⟩")
  (#set! @left_brace conceal "￨"))

((call
  item: (ident) @cmd
  "(" @left_brace
  (formula)
  "," @comma
  (formula)
  ")" @right_brace)
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "braket")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @comma conceal "￨")
  (#set! @right_brace conceal "⟩"))

((call
  item: (ident) @cmd
  "(" @left_brace
  (formula)
  "," @comma
  (formula)
  "," @comma
  (formula)
  ")" @right_brace)
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "mel")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @comma conceal "￨")
  (#set! @right_brace conceal "⟩"))

((call
  item: (ident) @_cmd
  "(" @left_brace
  .
  (formula) @typ_phy_symbol
  (formula
    .
    [
      (_) @sup_symbol
      (_) @sub_symbol
    ]
    .
    (_))
  ")" @right_brace)
  (#has-ancestor? @_cmd math formula)
  (#eq? @_cmd "tensor")
  (#eq? @sup_symbol "+")
  (#eq? @sub_symbol "-")
  (#set! @_cmd conceal "")
  (#set! @sup_symbol conceal "^")
  (#set! @sub_symbol conceal "_")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal ""))

((call
  item: (ident) @cmd
  "("
  .
  (formula
    (_) @typ_phy_symbol)
  ")")
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "tensor")
  (#set-conceal! @typ_phy_symbol "conceal"))

((call
  item: (ident) @cmd
  "("
  "," @comma
  ")")
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "tensor")
  (#set! @comma conceal ""))

((call
  item: (ident) @cmd
  "("
  (formula
    .
    (symbol) @sup_symbol
    .
    [
      (_) @sup_digit
      (_) @sup_letter
    ])
  ")")
  (#has-ancestor? @cmd math formula)
  (#match? @sup_digit "^([0-9]|[*+=()\\-])$")
  (#match? @sup_letter "^([a-pr-zABDEG-PRT-W]|alpha|beta|gamma|delta|epsilon|theta|iota|phi|chi)$")
  (#eq? @cmd "tensor")
  (#eq? @sup_symbol "+")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_digit "sup")
  (#set-sup! @sup_letter "sup"))

((call
  item: (ident) @cmd
  "("
  (formula
    .
    (symbol) @sub_symbol
    .
    [
      (_) @sub_digit
      (_) @sub_letter
    ])
  ")")
  (#has-ancestor? @cmd math formula)
  (#match? @sub_digit "^([0-9]|[+()=\\-])$")
  (#match? @sub_letter "^([aehijklmnoprstuvx]|beta|gamma|rho|phi|chi)$")
  (#eq? @cmd "tensor")
  (#eq? @sub_symbol "-")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_digit "sub")
  (#set-sub! @sub_letter "sub"))

(call
  item: (ident) @cmd
  "(" @left_brace
  "," @comma
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "isotope")
  (#set! @comma conceal "")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "(")
  (#set! @right_brace conceal ")"))

(call
  item: (ident) @cmd
  [
    (tagged
      field: (ident) @_ident_a
      ":" @sup_symbol)
    (tagged
      field: (ident) @_ident_z
      ":" @sub_symbol)
  ]
  (#has-ancestor? @cmd math formula)
  (#any-of? @cmd "isotope")
  (#eq? @_ident_a "a")
  (#eq? @_ident_z "z")
  (#set! @_ident_a conceal "")
  (#set! @_ident_z conceal "")
  (#set! @sup_symbol conceal "^")
  (#set! @sub_symbol conceal "_"))

(call
  item: (ident) @cmd
  "(" @left_brace
  .
  (formula)
  .
  "," @comma
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "taylorterm")
  (#set! @comma conceal "(")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal ")"))

(call
  item: (ident) @cmd
  "(" @left_brace
  (formula
    (group
      (formula
        (symbol) @punctuation.comma)))
  ")" @right_brace
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "BMEsymadd")
  (#set! @punctuation.comma conceal "+")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "")
  (#set! @right_brace conceal ""))

; TODO: For braket(ab) -> ⟨ab|ab⟩
((call
  item: (ident) @cmd
  "(" @left_brace
  (formula
    (letter) @first_letter
    (letter) @second_letter) @content
  ")" @right_brace)
  (#eq? @cmd "braket")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "⟩"))

; TODO: For ketbra(a,b) -> |ab⟩⟨ab|
((call
  item: (ident) @cmd
  "(" @left_brace
  (formula)
  "," @comma
  (formula)
  ")" @right_brace)
  (#has-ancestor? @cmd math formula)
  (#eq? @cmd "ketbra")
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "￨")
  (#set! @right_brace conceal "￨"))
