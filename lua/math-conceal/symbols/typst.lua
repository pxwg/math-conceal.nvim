local M = {}

M.conceal_math = [[
; Typst math conceals
; Based on Typst math mode syntax tree structure
; Math function calls with special symbols
(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral" "sqrt")
  ; (#has-ancestor? @func math formula)
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral"))
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

; Escape sequences - regex removed, Rust will filter
((escape) @typ_math_symbol
  (#set! priority 102)
  (#set-escape! @typ_math_symbol "conceal"))

; Special symbols in math mode
((symbol) @symbol
  (#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
  (#has-ancestor? @symbol math formula)
  (#set! priority 90))

; Conceal "frac" and replace with opening parenthesis
((call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac"))
  (#set! conceal "" @_frac_name)
  (#set! priority 1000))

; Replace comma with division slash
((call
  item: (ident) @_func_name
  (#eq? @_func_name "frac")
  (_)
  "," @punctuation.comma
  (_))
  (#set! conceal "/")
  (#set! priority 105))

; Conceal "abs" function name
(call
  item: (ident) @abs_name
  (#eq? @abs_name "abs")
  (#set! conceal "")
  (#set! priority 100))

; Conceal parentheses for abs function
(call
  item: (ident) @func_name
  "(" @left_paren
  (_)
  ")" @right_paren
  (#eq? @func_name "abs")
  (#set! conceal "|" @left_paren)
  (#set! conceal "|" @right_paren)
  (#set! priority 90))

; Math operators and symbols - regex removed, Rust will filter
((ident) @typ_math_symbol
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set! priority 101)
  (#set-conceal! @typ_math_symbol "conceal"))

; Math operators and symbols with modifiers - regex removed, Rust will filter  
((field) @typ_math_symbol
  (#set! priority 103)
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set-conceal! @typ_math_symbol "conceal"))

]]

M.conceal_font = [[
; Typst font style conceals - regex removed, Rust will filter
; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name
    "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double" "upright" )
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal ""))

; overline conceal for ident - regex removed, Rust will filter
(call
  item: (_) @typ_font_name
  (#any-of? @typ_font_name "overline" "tilde" "hat" "dot" "dot.double")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal "")
  (#set! priority 102))

(call
  item: (_) @typ_font_name
  (#any-of? @typ_font_name "overline")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal "")
  (#set! priority 102))

; Math function calls with special symbols
(call
  item: (ident) @typ_math_font
  (#any-of? @typ_math_font "dif")
  ; (#has-ancestor? @func math formula)
  (#set! conceal "d"))

(((ident) @typ_math_font
  (#any-of? @typ_math_font "dif"))
  ; (#has-ancestor? @conceal math formula)
  (#set! @typ_math_font conceal "d"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

]]

M.conceal_phy = [[
; Typst physics symbol conceals - regex removed, Rust will filter
; Physics constants and symbols
(call
  item: (ident) @typ_phy_symbol
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set! priority 98)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Physics units and quantities
((ident) @typ_phy_symbol
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set! priority 98)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Derivatives and differentials
((ident) @func
  (#any-of? @func "diff" "pdiff" "grad" "div" "curl" "laplacian")
  ; (#has-ancestor? @func math formula)
  (#set-conceal! @func "conceal"))

; Physics operators
((ident) @func
  (#any-of? @func "expval" "mel" "bra" "ket" "braket" "ketbra" "op")
  ; (#has-ancestor? @func math formula)
  (#set-conceal! @func "conceal"))

((call
        item: (ident) @cmd
        "(" @left_brace
        (#eq? @cmd "bra")
        (_)
        ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "|"))

((call
        item: (ident) @cmd
        "(" @left_brace
        (#eq? @cmd "ket")
        (_)
        ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @right_brace conceal "⟩")
  (#set! @left_brace conceal "|"))

;; For braket(a,b) -> ⟨a|b⟩
((call
      item: (ident) @cmd
      "(" @left_brace
      (#eq? @cmd "braket")
      (formula) @left_content
      "," @comma
      (formula) @right_content
      ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @comma conceal "|")
  (#set! @right_brace conceal "⟩"))

;; TODO: For braket(ab) -> ⟨ab|ab⟩
((call
      item: (ident) @cmd
      "(" @left_brace
      (#eq? @cmd "braket")
      (formula
        (letter) @first_letter
        (letter) @second_letter) @content
      ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "⟩"))

]]

M.conceal_delim = [[
; Typst delimiter conceals
; Math delimiters - parentheses, brackets, braces
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "lr" "left" "right")
  (#has-ancestor? @typ_math_delim math formula)
  (#set! conceal ""))

; Angle brackets
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "angle" "langle" "rangle")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Floor and ceiling
(call
  item: (ident) @typ_math_delim
  (#any-of? @typ_math_delim "floor" "ceil" "lfloor" "rfloor" "lceil" "rceil")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Norm delimiters
((call
        item: (ident) @cmd
        "(" @left_brace
        (_)
        ")" @right_brace)
 (#eq? @cmd "norm")
 (#set! @cmd conceal "")
 (#set! @left_brace conceal "‖")
 (#set! @right_brace conceal "‖"))

; Vertical bars and double bars
((symbol) @typ_math_delim
  (#any-of? @typ_math_delim "|" "||")
  (#has-ancestor? @typ_math_delim math formula)
  (#set-conceal! @typ_math_delim "conceal"))

; Inline math dollars and quotes
(math
  "$" @typ_inline_dollar
  (#set! @typ_inline_dollar conceal ""))

(string
  "\"" @typ_inline_quote
  (#set! @typ_inline_quote conceal ""))

(strong
  "*" @typ_inline_asterisk
  (#set! @typ_inline_asterisk conceal ""))

((align "&" @typ_inline_ampersand)
  (#set! @typ_inline_ampersand conceal ""))

]]

M.conceal_script = [[
; Typst script style conceals
; Superscript and subscript conceals
; A_a -> A(concealed sub:a)
(attach
  (_)
  "^" @sup_symbol
  sup: (_) @sup_object
  (#has-ancestor? @sup_object math formula)
  (#match? @sup_object "^[0-9a-z]$")
  (#set! priority 98)
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object "sup"))

; Subscript conceals
(attach
  (_)
  "_" @sub_symbol
  sub: (_) @sub_object
  (#has-ancestor? @sub_object math formula)
  (#match? @sub_object "^[0-9aehijklmnoprstuvx]$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object "sub"))

; Capture and conceal the opening parenthesis of the sub/supscript group
; For superscript with parentheses - hide both ^ and parentheses when content matches criteria
; Concealed symbol with lua_func: concealing the subscript and superscript symbols
; A_(a) -> A(concealed sub:a)
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (formula) @sup_letter
        ")" @close_paren)
      (#match? @sup_letter "^[a-z0-9]$")
      (#has-ancestor? @sup_letter math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")
      (#set! @sup_symbol conceal "")
      (#set-sup! @sup_letter)))

  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (formula) @sub_object
        ")" @close_paren)
      (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
      (#has-ancestor? @sub_object math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")
      (#set! @sub_symbol conceal "")
      (#set-sub! @sub_object)))

; Conceal the opening parenthesis of the subscript group while the formula has no space
; A_(xxx) -> A_xxx
  (formula
    (attach
      (_)
      "^" @sup_symbol
      sup: (group
        "(" @open_paren
        (_) @sup_object
        ")" @close_paren)
      (#match? @sup_object "^[A-Za-z0-9]+$")
      (#has-ancestor? @sup_object math formula)
      (#set! @open_paren conceal "")
      (#set! @close_paren conceal "")))

  (formula
    (attach
      (_)
      "_" @sub_symbol
      sub: (group
        "(" @open_paren
        (_) @sub_object
        ")" @close_paren)
      (#match? @sub_object "^[A-Za-z1-9]+$")
      (#has-ancestor? @sub_object math formula)
      (#set! @close_paren conceal "")
      (#set! @open_paren conceal "")))

]]

M.conceal_math_bare = [[
; Typst math conceals
; Based on Typst math mode syntax tree structure
; Math function calls with special symbols
(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral" "sqrt")
  ; (#has-ancestor? @func math formula)
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral"))
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set! priority 99)
  (#set-conceal! @typ_math_symbol "conceal"))

((escape) @typ_math_symbol
  (#set! priority 102)
  (#set-escape! @typ_math_symbol "conceal"))

; Special symbols in math mode
((symbol) @symbol
  (#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
  (#has-ancestor? @symbol math formula)
  (#set! priority 90))

; Conceal "frac" and replace with opening parenthesis
((call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac"))
  (#set! conceal "" @_frac_name)
  (#set! priority 1000))

; Replace comma with division slash
((call
  item: (ident) @_frac_name
  (#eq? @_frac_name "frac")
  (_)
  .
  "," @_comma
  (_))
  (#set! conceal "/" @_comma))

; Conceal "abs" function name
(call
  item: (ident) @abs_name
  (#eq? @abs_name "abs")
  (#set! conceal "")
  (#set! priority 100))

; Conceal parentheses for abs function
(call
  item: (ident) @func_name
  "(" @left_paren
  (_)
  ")" @right_paren
  (#eq? @func_name "abs")
  (#set! conceal "|" @left_paren)
  (#set! conceal "|" @right_paren)
  (#set! priority 90))

]]

M.conceal_greek = [[
; Typst Greek letter conceals - regex removed, Rust hash table will filter
; Greek letters as function calls
(call
  item: (ident) @typ_greek_symbol
  (#set! priority 102)
  (#set-conceal! @typ_greek_symbol "conceal"))
  ; (#has-ancestor? @conceal math formula)

; (#lua_func! @conceal "conceal"))
; Greek letters as direct identifiers
((ident) @typ_greek_symbol
  (#set! priority 102)
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set-conceal! @typ_greek_symbol "conceal"))

]]

return M
