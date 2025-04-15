; superscripts and subscripts conceals
(text
  word: (subscript) @conceal
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal text_mode label_definition)
  (#any-of? @conceal 
   "_0" "_1" "_2" "_3" "_4" "_5" "_6" "_7" "_8" "_9"
   "_a" "_e" "_h" "_i" "_j" "_k" "_l" "_m" "_n" "_o" "_p" "_r" "_s" "_t"
   "_u" "_v" "_x" "_\\.")
  (#lua_func! @conceal "conceal"))
  

(text
  word: (word) @conceal
  (#has-ancestor? @conceal subscript)
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal text_mode label_definition)
  (#any-of? @conceal
  "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f" "g" "h" "i" 
  "j" "k" "l" "m" "n" "o" "p" "r" "s" "t" "u" "v" "w" "x" "y" "z")
  (#lua_func! @conceal "conceal"))

(text
  word: (subscript) @conceal
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#any-of? @conceal "_+" "_-" "_/")
  (#lua_func! @conceal "conceal"))

(text
  word: (operator) @conceal
  (#has-ancestor? @conceal subscript)
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#any-of? @conceal "+" "-")
  (#lua_func! @conceal "conceal"))

(text
  word: (superscript) @conceal
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#any-of? @conceal
  "^0" "^1" "^2" "^3" "^4" "^5" "^6" "^7" "^8" "^9" 
  "^a" "^b" "^c" "^d" "^e" "^f" "^g" "^h" "^i" "^j" 
  "^k" "^l" "^m" "^n" "^o" "^p" "^r" "^s" "^t" "^u" 
  "^v" "^w" "^x" "^y" "^z" "^A" "^B" "^D" "^E" "^G" 
  "^H" "^I" "^J" "^K" "^L" "^M" "^N" "^O" "^P" "^R" 
  "^T" "^U" "^V" "^W")
  (#lua_func! @conceal "conceal"))

(text
  word: (superscript) @conceal
  (#any-of? @conceal
  "^+" "^-" "^<" "^>" "^/" "^=" "^\.")
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal text_mode label_definition)
  (#lua_func! @conceal "conceal"))
(text
  word: (operator) @conceal
  (#has-ancestor? @conceal superscript)
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#any-of? @conceal
  "+" "-" "<" ">" "/" "=" "\.")
  (#lua_func! @conceal "conceal"))

