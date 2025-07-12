; Typst math conceals
; Based on Typst math mode syntax tree structure

; Math function calls with special symbols
(call
  item: (ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral")
  ; (#has-ancestor? @func math formula)
  (#lua_func! @typ_math_symbol "conceal"))

(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol "root" "sum" "product" "integral"))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @typ_math_symbol "conceal"))

; Math operators and symbols
(((ident) @typ_math_symbol
 (#any-of? @typ_math_symbol
   "sum" "sqrt" "product" "integral" "nabla" "partial" "infinity" "emptyset"
   "aleph" "subset" "superset" "union" "intersection" "in" "notin" "element"
   "forall" "exists" "neg" "and" "or" "implies" "iff" "equiv" "approx" "neq"
   "leq" "geq" "ll" "gg" "pm" "mp" "times" "div" "cdot" "bullet" "circ" "ast"
   "cap" "cup" "sqcap" "sqcup" "vee" "wedge" "oplus" "ominus" "otimes" "oslash"
   "odot" "parallel" "perp" "angle" "triangle" "square" "diamond" "star"
   "dagger" "ddagger" "sharp" "flat" "natural" "clubs" "diamonds" "hearts"
   "spades" "dif" "diff" "quad"))
 (#lua_func! @typ_math_symbol "conceal"))

; Superscript and subscript handling
(attach
  sup: (_) @sup
  (#has-ancestor? @sup math formula)
  (#set! priority 110))

(attach
  sub: (_) @sub
  (#has-ancestor? @sub math formula)
  (#set! priority 110))

; Special symbols in math mode
((symbol) @symbol
(#any-of? @symbol "+" "-" "*" "/" "=" "<" ">" "(" ")" "[" "]" "{" "}")
(#has-ancestor? @symbol math formula)
(#set! priority 90))

; TODO: Conceal frac(a, b) to (a/b) conversion
