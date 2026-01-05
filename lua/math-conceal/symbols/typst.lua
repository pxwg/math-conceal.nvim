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

; (((ident) @typ_math_symbol
; (#any-of? @typ_math_symbol
; (#set-conceal! @typ_math_symbol "conceal"))
; Math operators and symbols
(((ident) @typ_math_symbol
  (#match? @typ_math_symbol "^(sum|sqrt|product|integral|nabla|partial|infinity|emptyset|aleph|subset|superset|union|intersection|in|notin|element|forall|exists|neg|and|or|implies|iff|equiv|approx|neq|leq|geq|ll|gg|pm|mp|times|div|cdot|bullet|circ|ast|cap|cup|sqcap|sqcup|vee|wedge|oplus|ominus|otimes|oslash|odot|parallel|perp|angle|triangle|square|diamond|star|dagger|ddagger|sharp|flat|natural|clubs|diamonds|hearts|spades|dif|diff|quad|amp|at|backslash|co|colon|comma|dot|dots|excl|quest|interrobang|hash|hyph|percent|copyright|permille|pilcrow|section|semi|slash|acute|breve|caret|caron|diaer|grave|macron|prime|plus|minus|ratio|eq|gt|lt|prec|succ|prop|nothing|without|complement|sect|oo|laplace|top|bot|not|xor|models|therefore|because|qed|compose|convolve|multimap|divides|wreath|diameter|join|degree|smash|bitcoin|dollar|euro|franc|lira|peso|pound|ruble|rupee|won|yen|ballot|checkmark|floral|refmark|servicemark|maltese|alpha|beta|chi|delta|epsilon|eta|gamma|iota|kai|kappa|lambda|mu|nu|ohm|omega|omicron|phi|pi|psi|rho|sigma|tau|theta|upsilon|xi|zeta|Alpha|Beta|Chi|Delta|Epsilon|Eta|Gamma|Iota|Kai|Kappa|Lambda|Mu|Nu|Omega|Omicron|Phi|Pi|Psi|Rho|Sigma|Tau|Theta|Upsilon|Xi|Zeta|alef|beth|bet|gimmel|gimel|shin|AA|BB|CC|DD|EE|FF|GG|HH|II|JJ|KK|LL|MM|NN|OO|PP|QQ|RR|SS|TT|UU|VV|WW|XX|YY|ZZ|ell|planck|angstrom|kelvin|Re|Im|thin|hat|tilde|mapsto|)$"))
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set! priority 101)
  (#set-conceal! @typ_math_symbol "conceal"))

((escape) @typ_math_symbol
  (#match? @typ_math_symbol "^\\\\(,|/)$")
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

; Math operators and symbols with modifiers
(((field) @typ_math_symbol
  (#match? @typ_math_symbol "^(Omega\\.inv|Theta\\.alt|acute\\.double|amp\\.inv|and\\.big|and\\.curly|and\\.dot|and\\.double|angle\\.acute|angle\\.arc|angle\\.arc\\.rev|angle\\.arc\\.right|angle\\.azimuth|angle\\.curly|angle\\.curly\\.l|angle\\.curly\\.r|angle\\.dot|angle\\.dot\\.l|angle\\.dot\\.r|angle\\.dot\\.right|angle\\.double|angle\\.double\\.l|angle\\.double\\.r|angle\\.l|angle\\.l\\.curly|angle\\.l\\.dot|angle\\.l\\.double|angle\\.oblique|angle\\.obtuse|angle\\.r|angle\\.r\\.curly|angle\\.r\\.dot|angle\\.r\\.double|angle\\.rev|angle\\.rev\\.arc|angle\\.rev\\.right|angle\\.rev\\.spheric|angle\\.right|angle\\.right\\.arc|angle\\.right\\.dot|angle\\.right\\.rev|angle\\.right\\.sq|angle\\.right\\.square|angle\\.s|angle\\.spatial|angle\\.spheric|angle\\.spheric\\.rev|angle\\.spheric\\.t|angle\\.spheric\\.top|angle\\.sq|angle\\.sq\\.right|angle\\.square|angle\\.square\\.right|angle\\.t|angle\\.t\\.spheric|angle\\.top|angle\\.top\\.spheric|approx\\.eq|approx\\.not|arrow\\.b|arrow\\.b\\.bar|arrow\\.b\\.curve|arrow\\.b\\.dashed|arrow\\.b\\.double|arrow\\.b\\.double\\.t|arrow\\.b\\.dstruck|arrow\\.b\\.filled|arrow\\.b\\.filled\\.t|arrow\\.b\\.quad|arrow\\.b\\.stop|arrow\\.b\\.stroked|arrow\\.b\\.stroked\\.t|arrow\\.b\\.struck|arrow\\.b\\.t|arrow\\.b\\.t\\.double|arrow\\.b\\.t\\.filled|arrow\\.b\\.t\\.stroked|arrow\\.b\\.triple|arrow\\.b\\.turn|arrow\\.b\\.twohead|arrow\\.bar|arrow\\.bar\\.b|arrow\\.bar\\.double|arrow\\.bar\\.double\\.l|arrow\\.bar\\.double\\.l\\.long|arrow\\.bar\\.double\\.long|arrow\\.bar\\.double\\.long\\.l|arrow\\.bar\\.double\\.long\\.r|arrow\\.bar\\.double\\.r|arrow\\.bar\\.double\\.r\\.long|arrow\\.bar\\.l|arrow\\.bar\\.l\\.double|arrow\\.bar\\.l\\.double\\.long|arrow\\.bar\\.l\\.long|arrow\\.bar\\.l\\.long\\.double|arrow\\.bar\\.l\\.twohead|arrow\\.bar\\.long|arrow\\.bar\\.long\\.double|arrow\\.bar\\.long\\.double\\.l|arrow\\.bar\\.long\\.double\\.r|arrow\\.bar\\.long\\.l|arrow\\.bar\\.long\\.l\\.double|arrow\\.bar\\.long\\.r|arrow\\.bar\\.long\\.r\\.double|arrow\\.bar\\.r|arrow\\.bar\\.r\\.double|arrow\\.bar\\.r\\.double\\.long|arrow\\.bar\\.r\\.long|arrow\\.bar\\.r\\.long\\.double|arrow\\.bar\\.r\\.twohead|arrow\\.bar\\.t|arrow\\.bar\\.twohead|arrow\\.bar\\.twohead\\.l|arrow\\.bar\\.twohead\\.r|arrow\\.bl|arrow\\.bl\\.double|arrow\\.bl\\.filled|arrow\\.bl\\.hook|arrow\\.bl\\.stroked|arrow\\.bl\\.tr|arrow\\.br|arrow\\.br\\.double|arrow\\.br\\.filled|arrow\\.br\\.hook|arrow\\.br\\.stroked|arrow\\.br\\.tl|arrow\\.ccw|arrow\\.ccw\\.half|arrow\\.curve|arrow\\.curve\\.b|arrow\\.curve\\.l|arrow\\.curve\\.r|arrow\\.curve\\.t|arrow\\.cw|arrow\\.cw\\.half|arrow\\.dashed|arrow\\.dashed\\.b|arrow\\.dashed\\.l|arrow\\.dashed\\.r|arrow\\.dashed\\.t|arrow\\.dotted|arrow\\.dotted\\.l|arrow\\.dotted\\.r|arrow\\.double|arrow\\.double\\.b|arrow\\.double\\.b\\.t|arrow\\.double\\.bar|arrow\\.double\\.bar\\.l|arrow\\.double\\.bar\\.l\\.long|arrow\\.double\\.bar\\.long|arrow\\.double\\.bar\\.long\\.l|arrow\\.double\\.bar\\.long\\.r|arrow\\.double\\.bar\\.r|arrow\\.double\\.bar\\.r\\.long|arrow\\.double\\.bl|arrow\\.double\\.br|arrow\\.double\\.l|arrow\\.double\\.l\\.bar|arrow\\.double\\.l\\.bar\\.long|arrow\\.double\\.l\\.long|arrow\\.double\\.l\\.long\\.bar|arrow\\.double\\.l\\.long\\.r|arrow\\.double\\.l\\.not|arrow\\.double\\.l\\.not\\.r|arrow\\.double\\.l\\.r|arrow\\.double\\.l\\.r\\.long|arrow\\.double\\.l\\.r\\.not|arrow\\.double\\.l\\.r\\.struck|arrow\\.double\\.l\\.struck|arrow\\.double\\.l\\.struck\\.r|arrow\\.double\\.long|arrow\\.double\\.long\\.bar|arrow\\.double\\.long\\.bar\\.l|arrow\\.double\\.long\\.bar\\.r|arrow\\.double\\.long\\.l|arrow\\.double\\.long\\.l\\.bar|arrow\\.double\\.long\\.l\\.r|arrow\\.double\\.long\\.r|arrow\\.double\\.long\\.r\\.bar|arrow\\.double\\.long\\.r\\.l|arrow\\.double\\.not|arrow\\.double\\.not\\.l|arrow\\.double\\.not\\.l\\.r|arrow\\.double\\.not\\.r|arrow\\.double\\.not\\.r\\.l|arrow\\.double\\.r|arrow\\.double\\.r\\.bar|arrow\\.double\\.r\\.bar\\.long|arrow\\.double\\.r\\.l|arrow\\.double\\.r\\.l\\.long|arrow\\.double\\.r\\.l\\.not|arrow\\.double\\.r\\.l\\.struck|arrow\\.double\\.r\\.long|arrow\\.double\\.r\\.long\\.bar|arrow\\.double\\.r\\.long\\.l|arrow\\.double\\.r\\.not|arrow\\.double\\.r\\.not\\.l|arrow\\.double\\.r\\.struck|arrow\\.double\\.r\\.struck\\.l|arrow\\.double\\.struck|arrow\\.double\\.struck\\.l|arrow\\.double\\.struck\\.l\\.r|arrow\\.double\\.struck\\.r|arrow\\.double\\.struck\\.r\\.l|arrow\\.double\\.t|arrow\\.double\\.t\\.b|arrow\\.double\\.tl|arrow\\.double\\.tr|arrow\\.dstruck|arrow\\.dstruck\\.b|arrow\\.dstruck\\.l|arrow\\.dstruck\\.l\\.r|arrow\\.dstruck\\.l\\.tail|arrow\\.dstruck\\.l\\.tail\\.twohead|arrow\\.dstruck\\.l\\.twohead|arrow\\.dstruck\\.l\\.twohead\\.tail|arrow\\.dstruck\\.r|arrow\\.dstruck\\.r\\.l|arrow\\.dstruck\\.r\\.tail|arrow\\.dstruck\\.r\\.tail\\.twohead|arrow\\.dstruck\\.r\\.twohead|arrow\\.dstruck\\.r\\.twohead\\.tail|arrow\\.dstruck\\.t|arrow\\.dstruck\\.tail|arrow\\.dstruck\\.tail\\.l|arrow\\.dstruck\\.tail\\.l\\.twohead|arrow\\.dstruck\\.tail\\.r|arrow\\.dstruck\\.tail\\.r\\.twohead|arrow\\.dstruck\\.tail\\.twohead|arrow\\.dstruck\\.tail\\.twohead\\.l|arrow\\.dstruck\\.tail\\.twohead\\.r|arrow\\.dstruck\\.twohead|arrow\\.dstruck\\.twohead\\.l|arrow\\.dstruck\\.twohead\\.l\\.tail|arrow\\.dstruck\\.twohead\\.r|arrow\\.dstruck\\.twohead\\.r\\.tail|arrow\\.dstruck\\.twohead\\.tail|arrow\\.dstruck\\.twohead\\.tail\\.l|arrow\\.dstruck\\.twohead\\.tail\\.r|arrow\\.filled|arrow\\.filled\\.b|arrow\\.filled\\.b\\.t|arrow\\.filled\\.bl|arrow\\.filled\\.br|arrow\\.filled\\.l|arrow\\.filled\\.l\\.r|arrow\\.filled\\.r|arrow\\.filled\\.r\\.l|arrow\\.filled\\.t|arrow\\.filled\\.t\\.b|arrow\\.filled\\.tl|arrow\\.filled\\.tr|arrow\\.half|arrow\\.half\\.ccw|arrow\\.half\\.cw|arrow\\.hook|arrow\\.hook\\.bl|arrow\\.hook\\.br|arrow\\.hook\\.l|arrow\\.hook\\.r|arrow\\.hook\\.tl|arrow\\.hook\\.tr|arrow\\.l|arrow\\.l\\.bar|arrow\\.l\\.bar\\.double|arrow\\.l\\.bar\\.double\\.long|arrow\\.l\\.bar\\.long|arrow\\.l\\.bar\\.long\\.double|arrow\\.l\\.bar\\.twohead|arrow\\.l\\.curve|arrow\\.l\\.dashed|arrow\\.l\\.dotted|arrow\\.l\\.double|arrow\\.l\\.double\\.bar|arrow\\.l\\.double\\.bar\\.long|arrow\\.l\\.double\\.long|arrow\\.l\\.double\\.long\\.bar|arrow\\.l\\.double\\.long\\.r|arrow\\.l\\.double\\.not|arrow\\.l\\.double\\.not\\.r|arrow\\.l\\.double\\.r|arrow\\.l\\.double\\.r\\.long|arrow\\.l\\.double\\.r\\.not|arrow\\.l\\.double\\.r\\.struck|arrow\\.l\\.double\\.struck|arrow\\.l\\.double\\.struck\\.r|arrow\\.l\\.dstruck|arrow\\.l\\.dstruck\\.r|arrow\\.l\\.dstruck\\.tail|arrow\\.l\\.dstruck\\.tail\\.twohead|arrow\\.l\\.dstruck\\.twohead|arrow\\.l\\.dstruck\\.twohead\\.tail|arrow\\.l\\.filled|arrow\\.l\\.filled\\.r|arrow\\.l\\.hook|arrow\\.l\\.long|arrow\\.l\\.long\\.bar|arrow\\.l\\.long\\.bar\\.double|arrow\\.l\\.long\\.double|arrow\\.l\\.long\\.double\\.bar|arrow\\.l\\.long\\.double\\.r|arrow\\.l\\.long\\.r|arrow\\.l\\.long\\.r\\.double|arrow\\.l\\.long\\.squiggly|arrow\\.l\\.loop|arrow\\.l\\.not|arrow\\.l\\.not\\.double|arrow\\.l\\.not\\.double\\.r|arrow\\.l\\.not\\.r|arrow\\.l\\.not\\.r\\.double|arrow\\.l\\.open|arrow\\.l\\.open\\.r|arrow\\.l\\.quad|arrow\\.l\\.r|arrow\\.l\\.r\\.double|arrow\\.l\\.r\\.double\\.long|arrow\\.l\\.r\\.double\\.not|arrow\\.l\\.r\\.double\\.struck|arrow\\.l\\.r\\.dstruck|arrow\\.l\\.r\\.filled|arrow\\.l\\.r\\.long|arrow\\.l\\.r\\.long\\.double|arrow\\.l\\.r\\.not|arrow\\.l\\.r\\.not\\.double|arrow\\.l\\.r\\.open|arrow\\.l\\.r\\.stroked|arrow\\.l\\.r\\.struck|arrow\\.l\\.r\\.struck\\.double|arrow\\.l\\.r\\.wave|arrow\\.l\\.squiggly|arrow\\.l\\.squiggly\\.long|arrow\\.l\\.stop|arrow\\.l\\.stroked|arrow\\.l\\.stroked\\.r|arrow\\.l\\.struck|arrow\\.l\\.struck\\.double|arrow\\.l\\.struck\\.double\\.r|arrow\\.l\\.struck\\.r|arrow\\.l\\.struck\\.r\\.double|arrow\\.l\\.struck\\.tail|arrow\\.l\\.struck\\.tail\\.twohead|arrow\\.l\\.struck\\.twohead|arrow\\.l\\.struck\\.twohead\\.tail|arrow\\.l\\.tail|arrow\\.l\\.tail\\.dstruck|arrow\\.l\\.tail\\.dstruck\\.twohead|arrow\\.l\\.tail\\.struck|arrow\\.l\\.tail\\.struck\\.twohead|arrow\\.l\\.tail\\.twohead|arrow\\.l\\.tail\\.twohead\\.dstruck|arrow\\.l\\.tail\\.twohead\\.struck|arrow\\.l\\.tilde|arrow\\.l\\.triple|arrow\\.l\\.turn|arrow\\.l\\.twohead|arrow\\.l\\.twohead\\.bar|arrow\\.l\\.twohead\\.dstruck|arrow\\.l\\.twohead\\.dstruck\\.tail|arrow\\.l\\.twohead\\.struck|arrow\\.l\\.twohead\\.struck\\.tail|arrow\\.l\\.twohead\\.tail|arrow\\.l\\.twohead\\.tail\\.dstruck|arrow\\.l\\.twohead\\.tail\\.struck|arrow\\.l\\.wave|arrow\\.l\\.wave\\.r|arrow\\.long|arrow\\.long\\.bar|arrow\\.long\\.bar\\.double|arrow\\.long\\.bar\\.double\\.l|arrow\\.long\\.bar\\.double\\.r|arrow\\.long\\.bar\\.l|arrow\\.long\\.bar\\.l\\.double|arrow\\.long\\.bar\\.r|arrow\\.long\\.bar\\.r\\.double|arrow\\.long\\.double|arrow\\.long\\.double\\.bar|arrow\\.long\\.double\\.bar\\.l|arrow\\.long\\.double\\.bar\\.r|arrow\\.long\\.double\\.l|arrow\\.long\\.double\\.l\\.bar|arrow\\.long\\.double\\.l\\.r|arrow\\.long\\.double\\.r|arrow\\.long\\.double\\.r\\.bar|arrow\\.long\\.double\\.r\\.l|arrow\\.long\\.l|arrow\\.long\\.l\\.bar|arrow\\.long\\.l\\.bar\\.double|arrow\\.long\\.l\\.double|arrow\\.long\\.l\\.double\\.bar|arrow\\.long\\.l\\.double\\.r|arrow\\.long\\.l\\.r|arrow\\.long\\.l\\.r\\.double|arrow\\.long\\.l\\.squiggly|arrow\\.long\\.r|arrow\\.long\\.r\\.bar|arrow\\.long\\.r\\.bar\\.double|arrow\\.long\\.r\\.double|arrow\\.long\\.r\\.double\\.bar|arrow\\.long\\.r\\.double\\.l|arrow\\.long\\.r\\.l|arrow\\.long\\.r\\.l\\.double|arrow\\.long\\.r\\.squiggly|arrow\\.long\\.squiggly|arrow\\.long\\.squiggly\\.l|arrow\\.long\\.squiggly\\.r|arrow\\.loop|arrow\\.loop\\.l|arrow\\.loop\\.r|arrow\\.not|arrow\\.not\\.double|arrow\\.not\\.double\\.l|arrow\\.not\\.double\\.l\\.r|arrow\\.not\\.double\\.r|arrow\\.not\\.double\\.r\\.l|arrow\\.not\\.l|arrow\\.not\\.l\\.double|arrow\\.not\\.l\\.double\\.r|arrow\\.not\\.l\\.r|arrow\\.not\\.l\\.r\\.double|arrow\\.not\\.r|arrow\\.not\\.r\\.double|arrow\\.not\\.r\\.double\\.l|arrow\\.not\\.r\\.l|arrow\\.not\\.r\\.l\\.double|arrow\\.open|arrow\\.open\\.l|arrow\\.open\\.l\\.r|arrow\\.open\\.r|arrow\\.open\\.r\\.l|arrow\\.quad|arrow\\.quad\\.b|arrow\\.quad\\.l|arrow\\.quad\\.r|arrow\\.quad\\.t|arrow\\.r|arrow\\.r\\.bar|arrow\\.r\\.bar\\.double|arrow\\.r\\.bar\\.double\\.long|arrow\\.r\\.bar\\.long|arrow\\.r\\.bar\\.long\\.double|arrow\\.r\\.bar\\.twohead|arrow\\.r\\.curve|arrow\\.r\\.dashed|arrow\\.r\\.dotted|arrow\\.r\\.double|arrow\\.r\\.double\\.bar|arrow\\.r\\.double\\.bar\\.long|arrow\\.r\\.double\\.l|arrow\\.r\\.double\\.l\\.long|arrow\\.r\\.double\\.l\\.not|arrow\\.r\\.double\\.l\\.struck|arrow\\.r\\.double\\.long|arrow\\.r\\.double\\.long\\.bar|arrow\\.r\\.double\\.long\\.l|arrow\\.r\\.double\\.not|arrow\\.r\\.double\\.not\\.l|arrow\\.r\\.double\\.struck|arrow\\.r\\.double\\.struck\\.l|arrow\\.r\\.dstruck|arrow\\.r\\.dstruck\\.l|arrow\\.r\\.dstruck\\.tail|arrow\\.r\\.dstruck\\.tail\\.twohead|arrow\\.r\\.dstruck\\.twohead|arrow\\.r\\.dstruck\\.twohead\\.tail|arrow\\.r\\.filled|arrow\\.r\\.filled\\.l|arrow\\.r\\.hook|arrow\\.r\\.l|arrow\\.r\\.l\\.double|arrow\\.r\\.l\\.double\\.long|arrow\\.r\\.l\\.double\\.not|arrow\\.r\\.l\\.double\\.struck|arrow\\.r\\.l\\.dstruck|arrow\\.r\\.l\\.filled|arrow\\.r\\.l\\.long|arrow\\.r\\.l\\.long\\.double|arrow\\.r\\.l\\.not|arrow\\.r\\.l\\.not\\.double|arrow\\.r\\.l\\.open|arrow\\.r\\.l\\.stroked|arrow\\.r\\.l\\.struck|arrow\\.r\\.l\\.struck\\.double|arrow\\.r\\.l\\.wave|arrow\\.r\\.long|arrow\\.r\\.long\\.bar|arrow\\.r\\.long\\.bar\\.double|arrow\\.r\\.long\\.double|arrow\\.r\\.long\\.double\\.bar|arrow\\.r\\.long\\.double\\.l|arrow\\.r\\.long\\.l|arrow\\.r\\.long\\.l\\.double|arrow\\.r\\.long\\.squiggly|arrow\\.r\\.loop|arrow\\.r\\.not|arrow\\.r\\.not\\.double|arrow\\.r\\.not\\.double\\.l|arrow\\.r\\.not\\.l|arrow\\.r\\.not\\.l\\.double|arrow\\.r\\.open|arrow\\.r\\.open\\.l|arrow\\.r\\.quad|arrow\\.r\\.squiggly|arrow\\.r\\.squiggly\\.long|arrow\\.r\\.stop|arrow\\.r\\.stroked|arrow\\.r\\.stroked\\.l|arrow\\.r\\.struck|arrow\\.r\\.struck\\.double|arrow\\.r\\.struck\\.double\\.l|arrow\\.r\\.struck\\.l|arrow\\.r\\.struck\\.l\\.double|arrow\\.r\\.struck\\.tail|arrow\\.r\\.struck\\.tail\\.twohead|arrow\\.r\\.struck\\.twohead|arrow\\.r\\.struck\\.twohead\\.tail|arrow\\.r\\.tail|arrow\\.r\\.tail\\.dstruck|arrow\\.r\\.tail\\.dstruck\\.twohead|arrow\\.r\\.tail\\.struck|arrow\\.r\\.tail\\.struck\\.twohead|arrow\\.r\\.tail\\.twohead|arrow\\.r\\.tail\\.twohead\\.dstruck|arrow\\.r\\.tail\\.twohead\\.struck|arrow\\.r\\.tilde|arrow\\.r\\.triple|arrow\\.r\\.turn|arrow\\.r\\.twohead|arrow\\.r\\.twohead\\.bar|arrow\\.r\\.twohead\\.dstruck|arrow\\.r\\.twohead\\.dstruck\\.tail|arrow\\.r\\.twohead\\.struck|arrow\\.r\\.twohead\\.struck\\.tail|arrow\\.r\\.twohead\\.tail|arrow\\.r\\.twohead\\.tail\\.dstruck|arrow\\.r\\.twohead\\.tail\\.struck|arrow\\.r\\.wave|arrow\\.r\\.wave\\.l|arrow\\.squiggly|arrow\\.squiggly\\.l|arrow\\.squiggly\\.l\\.long|arrow\\.squiggly\\.long|arrow\\.squiggly\\.long\\.l|arrow\\.squiggly\\.long\\.r|arrow\\.squiggly\\.r|arrow\\.squiggly\\.r\\.long|arrow\\.stop|arrow\\.stop\\.b|arrow\\.stop\\.l|arrow\\.stop\\.r|arrow\\.stop\\.t|arrow\\.stroked|arrow\\.stroked\\.b|arrow\\.stroked\\.b\\.t|arrow\\.stroked\\.bl|arrow\\.stroked\\.br|arrow\\.stroked\\.l|arrow\\.stroked\\.l\\.r|arrow\\.stroked\\.r|arrow\\.stroked\\.r\\.l|arrow\\.stroked\\.t|arrow\\.stroked\\.t\\.b|arrow\\.stroked\\.tl|arrow\\.stroked\\.tr|arrow\\.struck|arrow\\.struck\\.b|arrow\\.struck\\.double|arrow\\.struck\\.double\\.l|arrow\\.struck\\.double\\.l\\.r|arrow\\.struck\\.double\\.r|arrow\\.struck\\.double\\.r\\.l|arrow\\.struck\\.l|arrow\\.struck\\.l\\.double|arrow\\.struck\\.l\\.double\\.r|arrow\\.struck\\.l\\.r|arrow\\.struck\\.l\\.r\\.double|arrow\\.struck\\.l\\.tail|arrow\\.struck\\.l\\.tail\\.twohead|arrow\\.struck\\.l\\.twohead|arrow\\.struck\\.l\\.twohead\\.tail|arrow\\.struck\\.r|arrow\\.struck\\.r\\.double|arrow\\.struck\\.r\\.double\\.l|arrow\\.struck\\.r\\.l|arrow\\.struck\\.r\\.l\\.double|arrow\\.struck\\.r\\.tail|arrow\\.struck\\.r\\.tail\\.twohead|arrow\\.struck\\.r\\.twohead|arrow\\.struck\\.r\\.twohead\\.tail|arrow\\.struck\\.t|arrow\\.struck\\.tail|arrow\\.struck\\.tail\\.l|arrow\\.struck\\.tail\\.l\\.twohead|arrow\\.struck\\.tail\\.r|arrow\\.struck\\.tail\\.r\\.twohead|arrow\\.struck\\.tail\\.twohead|arrow\\.struck\\.tail\\.twohead\\.l|arrow\\.struck\\.tail\\.twohead\\.r|arrow\\.struck\\.twohead|arrow\\.struck\\.twohead\\.l|arrow\\.struck\\.twohead\\.l\\.tail|arrow\\.struck\\.twohead\\.r|arrow\\.struck\\.twohead\\.r\\.tail|arrow\\.struck\\.twohead\\.tail|arrow\\.struck\\.twohead\\.tail\\.l|arrow\\.struck\\.twohead\\.tail\\.r|arrow\\.t|arrow\\.t\\.b|arrow\\.t\\.b\\.double|arrow\\.t\\.b\\.filled|arrow\\.t\\.b\\.stroked|arrow\\.t\\.bar|arrow\\.t\\.curve|arrow\\.t\\.dashed|arrow\\.t\\.double|arrow\\.t\\.double\\.b|arrow\\.t\\.dstruck|arrow\\.t\\.filled|arrow\\.t\\.filled\\.b|arrow\\.t\\.quad|arrow\\.t\\.stop|arrow\\.t\\.stroked|arrow\\.t\\.stroked\\.b|arrow\\.t\\.struck|arrow\\.t\\.triple|arrow\\.t\\.turn|arrow\\.t\\.twohead|arrow\\.tail|arrow\\.tail\\.dstruck|arrow\\.tail\\.dstruck\\.l|arrow\\.tail\\.dstruck\\.l\\.twohead|arrow\\.tail\\.dstruck\\.r|arrow\\.tail\\.dstruck\\.r\\.twohead|arrow\\.tail\\.dstruck\\.twohead|arrow\\.tail\\.dstruck\\.twohead\\.l|arrow\\.tail\\.dstruck\\.twohead\\.r|arrow\\.tail\\.l|arrow\\.tail\\.l\\.dstruck|arrow\\.tail\\.l\\.dstruck\\.twohead|arrow\\.tail\\.l\\.struck|arrow\\.tail\\.l\\.struck\\.twohead|arrow\\.tail\\.l\\.twohead|arrow\\.tail\\.l\\.twohead\\.dstruck|arrow\\.tail\\.l\\.twohead\\.struck|arrow\\.tail\\.r|arrow\\.tail\\.r\\.dstruck|arrow\\.tail\\.r\\.dstruck\\.twohead|arrow\\.tail\\.r\\.struck|arrow\\.tail\\.r\\.struck\\.twohead|arrow\\.tail\\.r\\.twohead|arrow\\.tail\\.r\\.twohead\\.dstruck|arrow\\.tail\\.r\\.twohead\\.struck|arrow\\.tail\\.struck|arrow\\.tail\\.struck\\.l|arrow\\.tail\\.struck\\.l\\.twohead|arrow\\.tail\\.struck\\.r|arrow\\.tail\\.struck\\.r\\.twohead|arrow\\.tail\\.struck\\.twohead|arrow\\.tail\\.struck\\.twohead\\.l|arrow\\.tail\\.struck\\.twohead\\.r|arrow\\.tail\\.twohead|arrow\\.tail\\.twohead\\.dstruck|arrow\\.tail\\.twohead\\.dstruck\\.l|arrow\\.tail\\.twohead\\.dstruck\\.r|arrow\\.tail\\.twohead\\.l|arrow\\.tail\\.twohead\\.l\\.dstruck|arrow\\.tail\\.twohead\\.l\\.struck|arrow\\.tail\\.twohead\\.r|arrow\\.tail\\.twohead\\.r\\.dstruck|arrow\\.tail\\.twohead\\.r\\.struck|arrow\\.tail\\.twohead\\.struck|arrow\\.tail\\.twohead\\.struck\\.l|arrow\\.tail\\.twohead\\.struck\\.r|arrow\\.tilde|arrow\\.tilde\\.l|arrow\\.tilde\\.r|arrow\\.tl|arrow\\.tl\\.br|arrow\\.tl\\.double|arrow\\.tl\\.filled|arrow\\.tl\\.hook|arrow\\.tl\\.stroked|arrow\\.tr|arrow\\.tr\\.bl|arrow\\.tr\\.double|arrow\\.tr\\.filled|arrow\\.tr\\.hook|arrow\\.tr\\.stroked|arrow\\.triple|arrow\\.triple\\.b|arrow\\.triple\\.l|arrow\\.triple\\.r|arrow\\.triple\\.t|arrow\\.turn|arrow\\.turn\\.b|arrow\\.turn\\.l|arrow\\.turn\\.r|arrow\\.turn\\.t|arrow\\.twohead|arrow\\.twohead\\.b|arrow\\.twohead\\.bar|arrow\\.twohead\\.bar\\.l|arrow\\.twohead\\.bar\\.r|arrow\\.twohead\\.dstruck|arrow\\.twohead\\.dstruck\\.l|arrow\\.twohead\\.dstruck\\.l\\.tail|arrow\\.twohead\\.dstruck\\.r|arrow\\.twohead\\.dstruck\\.r\\.tail|arrow\\.twohead\\.dstruck\\.tail|arrow\\.twohead\\.dstruck\\.tail\\.l|arrow\\.twohead\\.dstruck\\.tail\\.r|arrow\\.twohead\\.l|arrow\\.twohead\\.l\\.bar|arrow\\.twohead\\.l\\.dstruck|arrow\\.twohead\\.l\\.dstruck\\.tail|arrow\\.twohead\\.l\\.struck|arrow\\.twohead\\.l\\.struck\\.tail|arrow\\.twohead\\.l\\.tail|arrow\\.twohead\\.l\\.tail\\.dstruck|arrow\\.twohead\\.l\\.tail\\.struck|arrow\\.twohead\\.r|arrow\\.twohead\\.r\\.bar|arrow\\.twohead\\.r\\.dstruck|arrow\\.twohead\\.r\\.dstruck\\.tail|arrow\\.twohead\\.r\\.struck|arrow\\.twohead\\.r\\.struck\\.tail|arrow\\.twohead\\.r\\.tail|arrow\\.twohead\\.r\\.tail\\.dstruck|arrow\\.twohead\\.r\\.tail\\.struck|arrow\\.twohead\\.struck|arrow\\.twohead\\.struck\\.l|arrow\\.twohead\\.struck\\.l\\.tail|arrow\\.twohead\\.struck\\.r|arrow\\.twohead\\.struck\\.r\\.tail|arrow\\.twohead\\.struck\\.tail|arrow\\.twohead\\.struck\\.tail\\.l|arrow\\.twohead\\.struck\\.tail\\.r|arrow\\.twohead\\.t|arrow\\.twohead\\.tail|arrow\\.twohead\\.tail\\.dstruck|arrow\\.twohead\\.tail\\.dstruck\\.l|arrow\\.twohead\\.tail\\.dstruck\\.r|arrow\\.twohead\\.tail\\.l|arrow\\.twohead\\.tail\\.l\\.dstruck|arrow\\.twohead\\.tail\\.l\\.struck|arrow\\.twohead\\.tail\\.r|arrow\\.twohead\\.tail\\.r\\.dstruck|arrow\\.twohead\\.tail\\.r\\.struck|arrow\\.twohead\\.tail\\.struck|arrow\\.twohead\\.tail\\.struck\\.l|arrow\\.twohead\\.tail\\.struck\\.r|arrow\\.wave|arrow\\.wave\\.l|arrow\\.wave\\.l\\.r|arrow\\.wave\\.r|arrow\\.wave\\.r\\.l|arrow\\.zigzag|arrowhead\\.b|arrowhead\\.t|arrows\\.bb|arrows\\.bt|arrows\\.ll|arrows\\.lll|arrows\\.lr|arrows\\.lr\\.stop|arrows\\.rl|arrows\\.rr|arrows\\.rrr|arrows\\.stop|arrows\\.stop\\.lr|arrows\\.tb|arrows\\.tt|ast\\.basic|ast\\.circle|ast\\.double|ast\\.low|ast\\.o|ast\\.o\\.op|ast\\.op|ast\\.op\\.o|ast\\.small|ast\\.square|ast\\.triple|asymp\\.not|backslash\\.circle|backslash\\.not|backslash\\.o|bag\\.l|bag\\.r|ballot\\.check|ballot\\.check\\.heavy|ballot\\.cross|ballot\\.heavy|ballot\\.heavy\\.check|bar\\.broken|bar\\.broken\\.v|bar\\.circle|bar\\.circle\\.v|bar\\.double|bar\\.double\\.v|bar\\.h|bar\\.o|bar\\.o\\.v|bar\\.triple|bar\\.triple\\.v|bar\\.v|bar\\.v\\.broken|bar\\.v\\.circle|bar\\.v\\.double|bar\\.v\\.o|bar\\.v\\.triple|beta\\.alt|brace\\.b|brace\\.double|brace\\.double\\.l|brace\\.double\\.r|brace\\.l|brace\\.l\\.double|brace\\.l\\.stroked|brace\\.r|brace\\.r\\.double|brace\\.r\\.stroked|brace\\.stroked|brace\\.stroked\\.l|brace\\.stroked\\.r|brace\\.t|bracket\\.b|bracket\\.b\\.l|bracket\\.b\\.l\\.tick|bracket\\.b\\.r|bracket\\.b\\.r\\.tick|bracket\\.b\\.tick|bracket\\.b\\.tick\\.l|bracket\\.b\\.tick\\.r|bracket\\.double|bracket\\.double\\.l|bracket\\.double\\.r|bracket\\.l|bracket\\.l\\.b|bracket\\.l\\.b\\.tick|bracket\\.l\\.double|bracket\\.l\\.stroked|bracket\\.l\\.t|bracket\\.l\\.t\\.tick|bracket\\.l\\.tick|bracket\\.l\\.tick\\.b|bracket\\.l\\.tick\\.t|bracket\\.r|bracket\\.r\\.b|bracket\\.r\\.b\\.tick|bracket\\.r\\.double|bracket\\.r\\.stroked|bracket\\.r\\.t|bracket\\.r\\.t\\.tick|bracket\\.r\\.tick|bracket\\.r\\.tick\\.b|bracket\\.r\\.tick\\.t|bracket\\.stroked|bracket\\.stroked\\.l|bracket\\.stroked\\.r|bracket\\.t|bracket\\.t\\.l|bracket\\.t\\.l\\.tick|bracket\\.t\\.r|bracket\\.t\\.r\\.tick|bracket\\.t\\.tick|bracket\\.t\\.tick\\.l|bracket\\.t\\.tick\\.r|bracket\\.tick|bracket\\.tick\\.b|bracket\\.tick\\.b\\.l|bracket\\.tick\\.b\\.r|bracket\\.tick\\.l|bracket\\.tick\\.l\\.b|bracket\\.tick\\.l\\.t|bracket\\.tick\\.r|bracket\\.tick\\.r\\.b|bracket\\.tick\\.r\\.t|bracket\\.tick\\.t|bracket\\.tick\\.t\\.l|bracket\\.tick\\.t\\.r|bullet\\.hole|bullet\\.hyph|bullet\\.l|bullet\\.o|bullet\\.o\\.stroked|bullet\\.op|bullet\\.r|bullet\\.stroked|bullet\\.stroked\\.o|bullet\\.tri|cc\\.by|cc\\.nc|cc\\.nd|cc\\.public|cc\\.sa|cc\\.zero|ceil\\.l|ceil\\.r|checkmark\\.heavy|checkmark\\.light|chevron\\.closed|chevron\\.closed\\.l|chevron\\.closed\\.r|chevron\\.curly|chevron\\.curly\\.l|chevron\\.curly\\.r|chevron\\.dot|chevron\\.dot\\.l|chevron\\.dot\\.r|chevron\\.double|chevron\\.double\\.l|chevron\\.double\\.r|chevron\\.l|chevron\\.l\\.closed|chevron\\.l\\.curly|chevron\\.l\\.dot|chevron\\.l\\.double|chevron\\.r|chevron\\.r\\.closed|chevron\\.r\\.curly|chevron\\.r\\.dot|chevron\\.r\\.double|circle\\.big|circle\\.big\\.filled|circle\\.big\\.stroked|circle\\.dotted|circle\\.filled|circle\\.filled\\.big|circle\\.filled\\.small|circle\\.filled\\.tiny|circle\\.nested|circle\\.small|circle\\.small\\.filled|circle\\.small\\.stroked|circle\\.stroked|circle\\.stroked\\.big|circle\\.stroked\\.small|circle\\.stroked\\.tiny|circle\\.tiny|circle\\.tiny\\.filled|circle\\.tiny\\.stroked|colon\\.currency|colon\\.double|colon\\.double\\.eq|colon\\.eq|colon\\.eq\\.double|colon\\.op|colon\\.op\\.tri|colon\\.tri|colon\\.tri\\.op|comma\\.inv|comma\\.rev|compose\\.o|convolve\\.o|copyright\\.sound|corner\\.b|corner\\.b\\.l|corner\\.b\\.r|corner\\.l|corner\\.l\\.b|corner\\.l\\.t|corner\\.r|corner\\.r\\.b|corner\\.r\\.t|corner\\.t|corner\\.t\\.l|corner\\.t\\.r|crossmark\\.heavy|dagger\\.double|dagger\\.inv|dagger\\.l|dagger\\.r|dagger\\.triple|dash\\.circle|dash\\.colon|dash\\.double|dash\\.double\\.wave|dash\\.em|dash\\.em\\.three|dash\\.em\\.two|dash\\.en|dash\\.fig|dash\\.o|dash\\.three|dash\\.three\\.em|dash\\.two|dash\\.two\\.em|dash\\.wave|dash\\.wave\\.double|diamond\\.dot|diamond\\.dot\\.stroked|diamond\\.filled|diamond\\.filled\\.medium|diamond\\.filled\\.small|diamond\\.medium|diamond\\.medium\\.filled|diamond\\.medium\\.stroked|diamond\\.small|diamond\\.small\\.filled|diamond\\.small\\.stroked|diamond\\.stroked|diamond\\.stroked\\.dot|diamond\\.stroked\\.medium|diamond\\.stroked\\.small|die\\.five|die\\.four|die\\.one|die\\.six|die\\.three|die\\.two|div\\.circle|div\\.o|div\\.o\\.slanted|div\\.slanted|div\\.slanted\\.o|divides\\.not|divides\\.not\\.rev|divides\\.rev|divides\\.rev\\.not|divides\\.struck|dot\\.basic|dot\\.big|dot\\.big\\.circle|dot\\.big\\.o|dot\\.c|dot\\.circle|dot\\.circle\\.big|dot\\.double|dot\\.o|dot\\.o\\.big|dot\\.op|dot\\.quad|dot\\.square|dot\\.triple|dotless\\.i|dotless\\.j|dots\\.c|dots\\.c\\.h|dots\\.down|dots\\.h|dots\\.h\\.c|dots\\.up|dots\\.v|earth\\.alt|ellipse\\.filled|ellipse\\.filled\\.h|ellipse\\.filled\\.v|ellipse\\.h|ellipse\\.h\\.filled|ellipse\\.h\\.stroked|ellipse\\.stroked|ellipse\\.stroked\\.h|ellipse\\.stroked\\.v|ellipse\\.v|ellipse\\.v\\.filled|ellipse\\.v\\.stroked|emptyset\\.arrow|emptyset\\.arrow\\.l|emptyset\\.arrow\\.r|emptyset\\.bar|emptyset\\.circle|emptyset\\.l|emptyset\\.l\\.arrow|emptyset\\.r|emptyset\\.r\\.arrow|emptyset\\.rev|epsilon\\.alt|epsilon\\.alt\\.rev|epsilon\\.rev|epsilon\\.rev\\.alt|eq\\.circle|eq\\.colon|eq\\.def|eq\\.delta|eq\\.dots|eq\\.dots\\.down|eq\\.dots\\.up|eq\\.down|eq\\.down\\.dots|eq\\.equi|eq\\.est|eq\\.gt|eq\\.lt|eq\\.m|eq\\.not|eq\\.not\\.triple|eq\\.o|eq\\.prec|eq\\.quad|eq\\.quest|eq\\.small|eq\\.star|eq\\.succ|eq\\.triple|eq\\.triple\\.not|eq\\.up|eq\\.up\\.dots|equiv\\.not|errorbar\\.circle|errorbar\\.circle\\.filled|errorbar\\.circle\\.stroked|errorbar\\.diamond|errorbar\\.diamond\\.filled|errorbar\\.diamond\\.stroked|errorbar\\.filled|errorbar\\.filled\\.circle|errorbar\\.filled\\.diamond|errorbar\\.filled\\.square|errorbar\\.square|errorbar\\.square\\.filled|errorbar\\.square\\.stroked|errorbar\\.stroked|errorbar\\.stroked\\.circle|errorbar\\.stroked\\.diamond|errorbar\\.stroked\\.square|excl\\.double|excl\\.inv|excl\\.quest|exists\\.not|fence\\.dotted|fence\\.double|fence\\.double\\.l|fence\\.double\\.r|fence\\.l|fence\\.l\\.double|fence\\.r|fence\\.r\\.double|flat\\.b|flat\\.double|flat\\.quarter|flat\\.t|floor\\.l|floor\\.r|floral\\.l|floral\\.r|forces\\.not|gt\\.approx|gt\\.circle|gt\\.dot|gt\\.double|gt\\.eq|gt\\.eq\\.lt|gt\\.eq\\.not|gt\\.eq\\.not\\.tri|gt\\.eq\\.slant|gt\\.eq\\.tri|gt\\.eq\\.tri\\.not|gt\\.equiv|gt\\.lt|gt\\.lt\\.eq|gt\\.lt\\.not|gt\\.napprox|gt\\.neq|gt\\.nequiv|gt\\.nested|gt\\.nested\\.triple|gt\\.not|gt\\.not\\.eq|gt\\.not\\.eq\\.tri|gt\\.not\\.lt|gt\\.not\\.tilde|gt\\.not\\.tri|gt\\.not\\.tri\\.eq|gt\\.ntilde|gt\\.o|gt\\.slant|gt\\.slant\\.eq|gt\\.small|gt\\.tilde|gt\\.tilde\\.not|gt\\.tri|gt\\.tri\\.eq|gt\\.tri\\.eq\\.not|gt\\.tri\\.not|gt\\.tri\\.not\\.eq|gt\\.triple|gt\\.triple\\.nested|harpoon\\.bar|harpoon\\.bar\\.bl|harpoon\\.bar\\.br|harpoon\\.bar\\.lb|harpoon\\.bar\\.lt|harpoon\\.bar\\.rb|harpoon\\.bar\\.rt|harpoon\\.bar\\.tl|harpoon\\.bar\\.tr|harpoon\\.bl|harpoon\\.bl\\.bar|harpoon\\.bl\\.stop|harpoon\\.bl\\.tl|harpoon\\.bl\\.tr|harpoon\\.br|harpoon\\.br\\.bar|harpoon\\.br\\.stop|harpoon\\.br\\.tl|harpoon\\.br\\.tr|harpoon\\.lb|harpoon\\.lb\\.bar|harpoon\\.lb\\.rb|harpoon\\.lb\\.rt|harpoon\\.lb\\.stop|harpoon\\.lt|harpoon\\.lt\\.bar|harpoon\\.lt\\.rb|harpoon\\.lt\\.rt|harpoon\\.lt\\.stop|harpoon\\.rb|harpoon\\.rb\\.bar|harpoon\\.rb\\.lb|harpoon\\.rb\\.lt|harpoon\\.rb\\.stop|harpoon\\.rt|harpoon\\.rt\\.bar|harpoon\\.rt\\.lb|harpoon\\.rt\\.lt|harpoon\\.rt\\.stop|harpoon\\.stop|harpoon\\.stop\\.bl|harpoon\\.stop\\.br|harpoon\\.stop\\.lb|harpoon\\.stop\\.lt|harpoon\\.stop\\.rb|harpoon\\.stop\\.rt|harpoon\\.stop\\.tl|harpoon\\.stop\\.tr|harpoon\\.tl|harpoon\\.tl\\.bar|harpoon\\.tl\\.bl|harpoon\\.tl\\.br|harpoon\\.tl\\.stop|harpoon\\.tr|harpoon\\.tr\\.bar|harpoon\\.tr\\.bl|harpoon\\.tr\\.br|harpoon\\.tr\\.stop|harpoons\\.blbr|harpoons\\.bltr|harpoons\\.lbrb|harpoons\\.ltlb|harpoons\\.ltrb|harpoons\\.ltrt|harpoons\\.rblb|harpoons\\.rtlb|harpoons\\.rtlt|harpoons\\.rtrb|harpoons\\.tlbr|harpoons\\.tltr|hexa\\.filled|hexa\\.stroked|hourglass\\.filled|hourglass\\.stroked|hyph\\.minus|hyph\\.nobreak|hyph\\.point|hyph\\.soft|in\\.not|in\\.not\\.rev|in\\.rev|in\\.rev\\.not|in\\.rev\\.small|in\\.small|in\\.small\\.rev|infinity\\.bar|infinity\\.incomplete|infinity\\.tie|integral\\.arrow|integral\\.arrow\\.hook|integral\\.ccw|integral\\.ccw\\.cont|integral\\.cont|integral\\.cont\\.ccw|integral\\.cont\\.cw|integral\\.cw|integral\\.cw\\.cont|integral\\.dash|integral\\.dash\\.double|integral\\.double|integral\\.double\\.dash|integral\\.hook|integral\\.hook\\.arrow|integral\\.inter|integral\\.quad|integral\\.sect|integral\\.slash|integral\\.square|integral\\.surf|integral\\.times|integral\\.triple|integral\\.union|integral\\.vol|inter\\.and|inter\\.big|inter\\.big\\.sq|inter\\.dot|inter\\.double|inter\\.double\\.sq|inter\\.sq|inter\\.sq\\.big|inter\\.sq\\.double|interleave\\.big|interleave\\.struck|interrobang\\.inv|iota\\.inv|join\\.l|join\\.l\\.r|join\\.r|join\\.r\\.l|kappa\\.alt|lat\\.eq|lozenge\\.filled|lozenge\\.filled\\.medium|lozenge\\.filled\\.small|lozenge\\.medium|lozenge\\.medium\\.filled|lozenge\\.medium\\.stroked|lozenge\\.small|lozenge\\.small\\.filled|lozenge\\.small\\.stroked|lozenge\\.stroked|lozenge\\.stroked\\.medium|lozenge\\.stroked\\.small|lt\\.approx|lt\\.circle|lt\\.dot|lt\\.double|lt\\.eq|lt\\.eq\\.gt|lt\\.eq\\.not|lt\\.eq\\.not\\.tri|lt\\.eq\\.slant|lt\\.eq\\.tri|lt\\.eq\\.tri\\.not|lt\\.equiv|lt\\.gt|lt\\.gt\\.eq|lt\\.gt\\.not|lt\\.napprox|lt\\.neq|lt\\.nequiv|lt\\.nested|lt\\.nested\\.triple|lt\\.not|lt\\.not\\.eq|lt\\.not\\.eq\\.tri|lt\\.not\\.gt|lt\\.not\\.tilde|lt\\.not\\.tri|lt\\.not\\.tri\\.eq|lt\\.ntilde|lt\\.o|lt\\.slant|lt\\.slant\\.eq|lt\\.small|lt\\.tilde|lt\\.tilde\\.not|lt\\.tri|lt\\.tri\\.eq|lt\\.tri\\.eq\\.not|lt\\.tri\\.not|lt\\.tri\\.not\\.eq|lt\\.triple|lt\\.triple\\.nested|mapsto\\.long|minus\\.circle|minus\\.dot|minus\\.o|minus\\.plus|minus\\.square|minus\\.tilde|minus\\.triangle|multimap\\.double|mustache\\.l|mustache\\.r|natural\\.b|natural\\.t|neptune\\.alt|note\\.alt|note\\.alt\\.eighth|note\\.alt\\.quarter|note\\.beamed|note\\.beamed\\.eighth|note\\.beamed\\.sixteenth|note\\.down|note\\.eighth|note\\.eighth\\.alt|note\\.eighth\\.beamed|note\\.grace|note\\.grace\\.slash|note\\.half|note\\.quarter|note\\.quarter\\.alt|note\\.sixteenth|note\\.sixteenth\\.beamed|note\\.slash|note\\.slash\\.grace|note\\.up|note\\.whole|nothing\\.arrow|nothing\\.arrow\\.l|nothing\\.arrow\\.r|nothing\\.bar|nothing\\.circle|nothing\\.l|nothing\\.l\\.arrow|nothing\\.r|nothing\\.r\\.arrow|nothing\\.rev|or\\.big|or\\.curly|or\\.dot|or\\.double|parallel\\.circle|parallel\\.eq|parallel\\.eq\\.slanted|parallel\\.eq\\.slanted\\.tilde|parallel\\.eq\\.tilde|parallel\\.eq\\.tilde\\.slanted|parallel\\.equiv|parallel\\.equiv\\.slanted|parallel\\.not|parallel\\.o|parallel\\.slanted|parallel\\.slanted\\.eq|parallel\\.slanted\\.eq\\.tilde|parallel\\.slanted\\.equiv|parallel\\.slanted\\.tilde|parallel\\.slanted\\.tilde\\.eq|parallel\\.struck|parallel\\.tilde|parallel\\.tilde\\.eq|parallel\\.tilde\\.eq\\.slanted|parallel\\.tilde\\.slanted|parallel\\.tilde\\.slanted\\.eq|parallelogram\\.filled|parallelogram\\.stroked|paren\\.b|paren\\.closed|paren\\.closed\\.l|paren\\.closed\\.r|paren\\.double|paren\\.double\\.l|paren\\.double\\.r|paren\\.flat|paren\\.flat\\.l|paren\\.flat\\.r|paren\\.l|paren\\.l\\.closed|paren\\.l\\.double|paren\\.l\\.flat|paren\\.l\\.stroked|paren\\.r|paren\\.r\\.closed|paren\\.r\\.double|paren\\.r\\.flat|paren\\.r\\.stroked|paren\\.stroked|paren\\.stroked\\.l|paren\\.stroked\\.r|paren\\.t|penta\\.filled|penta\\.stroked|perp\\.circle|perp\\.o|peso\\.philippine|phi\\.alt|pi\\.alt|pilcrow\\.rev|planck\\.reduce|plus\\.arrow|plus\\.arrow\\.circle|plus\\.arrow\\.o|plus\\.big|plus\\.big\\.circle|plus\\.big\\.o|plus\\.circle|plus\\.circle\\.arrow|plus\\.circle\\.big|plus\\.dot|plus\\.double|plus\\.l|plus\\.l\\.o|plus\\.minus|plus\\.o|plus\\.o\\.arrow|plus\\.o\\.big|plus\\.o\\.l|plus\\.o\\.r|plus\\.r|plus\\.r\\.o|plus\\.small|plus\\.square|plus\\.triangle|plus\\.triple|power\\.off|power\\.off\\.on|power\\.on|power\\.on\\.off|power\\.sleep|power\\.standby|prec\\.approx|prec\\.curly|prec\\.curly\\.eq|prec\\.curly\\.eq\\.not|prec\\.curly\\.not|prec\\.curly\\.not\\.eq|prec\\.double|prec\\.eq|prec\\.eq\\.curly|prec\\.eq\\.curly\\.not|prec\\.eq\\.not|prec\\.eq\\.not\\.curly|prec\\.equiv|prec\\.napprox|prec\\.neq|prec\\.nequiv|prec\\.not|prec\\.not\\.curly|prec\\.not\\.curly\\.eq|prec\\.not\\.eq|prec\\.not\\.eq\\.curly|prec\\.ntilde|prec\\.tilde|prime\\.double|prime\\.double\\.rev|prime\\.quad|prime\\.rev|prime\\.rev\\.double|prime\\.rev\\.triple|prime\\.triple|prime\\.triple\\.rev|product\\.co|quest\\.double|quest\\.excl|quest\\.inv|quote\\.angle|quote\\.angle\\.double|quote\\.angle\\.double\\.l|quote\\.angle\\.double\\.r|quote\\.angle\\.l|quote\\.angle\\.l\\.double|quote\\.angle\\.l\\.single|quote\\.angle\\.r|quote\\.angle\\.r\\.double|quote\\.angle\\.r\\.single|quote\\.angle\\.single|quote\\.angle\\.single\\.l|quote\\.angle\\.single\\.r|quote\\.chevron|quote\\.chevron\\.double|quote\\.chevron\\.double\\.l|quote\\.chevron\\.double\\.r|quote\\.chevron\\.l|quote\\.chevron\\.l\\.double|quote\\.chevron\\.l\\.single|quote\\.chevron\\.r|quote\\.chevron\\.r\\.double|quote\\.chevron\\.r\\.single|quote\\.chevron\\.single|quote\\.chevron\\.single\\.l|quote\\.chevron\\.single\\.r|quote\\.double|quote\\.double\\.angle|quote\\.double\\.angle\\.l|quote\\.double\\.angle\\.r|quote\\.double\\.chevron|quote\\.double\\.chevron\\.l|quote\\.double\\.chevron\\.r|quote\\.double\\.high|quote\\.double\\.l|quote\\.double\\.l\\.angle|quote\\.double\\.l\\.chevron|quote\\.double\\.low|quote\\.double\\.r|quote\\.double\\.r\\.angle|quote\\.double\\.r\\.chevron|quote\\.high|quote\\.high\\.double|quote\\.high\\.single|quote\\.l|quote\\.l\\.angle|quote\\.l\\.angle\\.double|quote\\.l\\.angle\\.single|quote\\.l\\.chevron|quote\\.l\\.chevron\\.double|quote\\.l\\.chevron\\.single|quote\\.l\\.double|quote\\.l\\.double\\.angle|quote\\.l\\.double\\.chevron|quote\\.l\\.single|quote\\.l\\.single\\.angle|quote\\.l\\.single\\.chevron|quote\\.low|quote\\.low\\.double|quote\\.low\\.single|quote\\.r|quote\\.r\\.angle|quote\\.r\\.angle\\.double|quote\\.r\\.angle\\.single|quote\\.r\\.chevron|quote\\.r\\.chevron\\.double|quote\\.r\\.chevron\\.single|quote\\.r\\.double|quote\\.r\\.double\\.angle|quote\\.r\\.double\\.chevron|quote\\.r\\.single|quote\\.r\\.single\\.angle|quote\\.r\\.single\\.chevron|quote\\.single|quote\\.single\\.angle|quote\\.single\\.angle\\.l|quote\\.single\\.angle\\.r|quote\\.single\\.chevron|quote\\.single\\.chevron\\.l|quote\\.single\\.chevron\\.r|quote\\.single\\.high|quote\\.single\\.l|quote\\.single\\.l\\.angle|quote\\.single\\.l\\.chevron|quote\\.single\\.low|quote\\.single\\.r|quote\\.single\\.r\\.angle|quote\\.single\\.r\\.chevron|rect\\.filled|rect\\.filled\\.h|rect\\.filled\\.v|rect\\.h|rect\\.h\\.filled|rect\\.h\\.stroked|rect\\.stroked|rect\\.stroked\\.h|rect\\.stroked\\.v|rect\\.v|rect\\.v\\.filled|rect\\.v\\.stroked|rest\\.eighth|rest\\.half|rest\\.measure|rest\\.measure\\.multiple|rest\\.multiple|rest\\.multiple\\.measure|rest\\.quarter|rest\\.sixteenth|rest\\.whole|rho\\.alt|rupee\\.generic|rupee\\.indian|rupee\\.tamil|rupee\\.wancho|sect\\.and|sect\\.big|sect\\.big\\.sq|sect\\.dot|sect\\.double|sect\\.double\\.sq|sect\\.sq|sect\\.sq\\.big|sect\\.sq\\.double|semi\\.inv|semi\\.rev|sharp\\.b|sharp\\.double|sharp\\.quarter|sharp\\.t|shell\\.b|shell\\.double|shell\\.double\\.l|shell\\.double\\.r|shell\\.filled|shell\\.filled\\.l|shell\\.filled\\.r|shell\\.l|shell\\.l\\.double|shell\\.l\\.filled|shell\\.l\\.stroked|shell\\.r|shell\\.r\\.double|shell\\.r\\.filled|shell\\.r\\.stroked|shell\\.stroked|shell\\.stroked\\.l|shell\\.stroked\\.r|shell\\.t|sigma\\.alt|slash\\.big|slash\\.double|slash\\.o|slash\\.triple|smt\\.eq|space\\.en|space\\.fig|space\\.hair|space\\.med|space\\.narrow|space\\.narrow\\.nobreak|space\\.nobreak|space\\.nobreak\\.narrow|space\\.punct|space\\.quad|space\\.quarter|space\\.sixth|space\\.thin|space\\.third|square\\.big|square\\.big\\.filled|square\\.big\\.stroked|square\\.dotted|square\\.dotted\\.stroked|square\\.filled|square\\.filled\\.big|square\\.filled\\.medium|square\\.filled\\.small|square\\.filled\\.tiny|square\\.medium|square\\.medium\\.filled|square\\.medium\\.stroked|square\\.rounded|square\\.rounded\\.stroked|square\\.small|square\\.small\\.filled|square\\.small\\.stroked|square\\.stroked|square\\.stroked\\.big|square\\.stroked\\.dotted|square\\.stroked\\.medium|square\\.stroked\\.rounded|square\\.stroked\\.small|square\\.stroked\\.tiny|square\\.tiny|square\\.tiny\\.filled|square\\.tiny\\.stroked|star\\.filled|star\\.op|star\\.stroked|subset\\.dot|subset\\.double|subset\\.eq|subset\\.eq\\.not|subset\\.eq\\.not\\.sq|subset\\.eq\\.sq|subset\\.eq\\.sq\\.not|subset\\.neq|subset\\.neq\\.sq|subset\\.not|subset\\.not\\.eq|subset\\.not\\.eq\\.sq|subset\\.not\\.sq|subset\\.not\\.sq\\.eq|subset\\.sq|subset\\.sq\\.eq|subset\\.sq\\.eq\\.not|subset\\.sq\\.neq|subset\\.sq\\.not|subset\\.sq\\.not\\.eq|succ\\.approx|succ\\.curly|succ\\.curly\\.eq|succ\\.curly\\.eq\\.not|succ\\.curly\\.not|succ\\.curly\\.not\\.eq|succ\\.double|succ\\.eq|succ\\.eq\\.curly|succ\\.eq\\.curly\\.not|succ\\.eq\\.not|succ\\.eq\\.not\\.curly|succ\\.equiv|succ\\.napprox|succ\\.neq|succ\\.nequiv|succ\\.not|succ\\.not\\.curly|succ\\.not\\.curly\\.eq|succ\\.not\\.eq|succ\\.not\\.eq\\.curly|succ\\.ntilde|succ\\.tilde|suit\\.club|suit\\.club\\.filled|suit\\.club\\.stroked|suit\\.diamond|suit\\.diamond\\.filled|suit\\.diamond\\.stroked|suit\\.filled|suit\\.filled\\.club|suit\\.filled\\.diamond|suit\\.filled\\.heart|suit\\.filled\\.spade|suit\\.heart|suit\\.heart\\.filled|suit\\.heart\\.stroked|suit\\.spade|suit\\.spade\\.filled|suit\\.spade\\.stroked|suit\\.stroked|suit\\.stroked\\.club|suit\\.stroked\\.diamond|suit\\.stroked\\.heart|suit\\.stroked\\.spade|sum\\.integral|supset\\.dot|supset\\.double|supset\\.eq|supset\\.eq\\.not|supset\\.eq\\.not\\.sq|supset\\.eq\\.sq|supset\\.eq\\.sq\\.not|supset\\.neq|supset\\.neq\\.sq|supset\\.not|supset\\.not\\.eq|supset\\.not\\.eq\\.sq|supset\\.not\\.sq|supset\\.not\\.sq\\.eq|supset\\.sq|supset\\.sq\\.eq|supset\\.sq\\.eq\\.not|supset\\.sq\\.neq|supset\\.sq\\.not|supset\\.sq\\.not\\.eq|tack\\.b|tack\\.b\\.big|tack\\.b\\.double|tack\\.b\\.short|tack\\.big|tack\\.big\\.b|tack\\.big\\.t|tack\\.double|tack\\.double\\.b|tack\\.double\\.l|tack\\.double\\.not|tack\\.double\\.not\\.r|tack\\.double\\.r|tack\\.double\\.r\\.not|tack\\.double\\.t|tack\\.l|tack\\.l\\.double|tack\\.l\\.long|tack\\.l\\.r|tack\\.l\\.short|tack\\.long|tack\\.long\\.l|tack\\.long\\.r|tack\\.not|tack\\.not\\.double|tack\\.not\\.double\\.r|tack\\.not\\.r|tack\\.not\\.r\\.double|tack\\.r|tack\\.r\\.double|tack\\.r\\.double\\.not|tack\\.r\\.l|tack\\.r\\.long|tack\\.r\\.not|tack\\.r\\.not\\.double|tack\\.r\\.short|tack\\.short|tack\\.short\\.b|tack\\.short\\.l|tack\\.short\\.r|tack\\.short\\.t|tack\\.t|tack\\.t\\.big|tack\\.t\\.double|tack\\.t\\.short|theta\\.alt|tilde\\.basic|tilde\\.dot|tilde\\.eq|tilde\\.eq\\.not|tilde\\.eq\\.rev|tilde\\.equiv|tilde\\.equiv\\.not|tilde\\.equiv\\.rev|tilde\\.nequiv|tilde\\.not|tilde\\.not\\.eq|tilde\\.not\\.equiv|tilde\\.op|tilde\\.rev|tilde\\.rev\\.eq|tilde\\.rev\\.equiv|tilde\\.triple|times\\.big|times\\.big\\.circle|times\\.big\\.o|times\\.circle|times\\.circle\\.big|times\\.div|times\\.hat|times\\.hat\\.o|times\\.l|times\\.l\\.o|times\\.l\\.three|times\\.o|times\\.o\\.big|times\\.o\\.hat|times\\.o\\.l|times\\.o\\.r|times\\.r|times\\.r\\.o|times\\.r\\.three|times\\.square|times\\.three|times\\.three\\.l|times\\.three\\.r|times\\.triangle|trademark\\.registered|trademark\\.service|triangle\\.b|triangle\\.b\\.filled|triangle\\.b\\.filled\\.small|triangle\\.b\\.small|triangle\\.b\\.small\\.filled|triangle\\.b\\.small\\.stroked|triangle\\.b\\.stroked|triangle\\.b\\.stroked\\.small|triangle\\.bl|triangle\\.bl\\.filled|triangle\\.bl\\.stroked|triangle\\.br|triangle\\.br\\.filled|triangle\\.br\\.stroked|triangle\\.dot|triangle\\.dot\\.stroked|triangle\\.filled|triangle\\.filled\\.b|triangle\\.filled\\.b\\.small|triangle\\.filled\\.bl|triangle\\.filled\\.br|triangle\\.filled\\.l|triangle\\.filled\\.l\\.small|triangle\\.filled\\.r|triangle\\.filled\\.r\\.small|triangle\\.filled\\.small|triangle\\.filled\\.small\\.b|triangle\\.filled\\.small\\.l|triangle\\.filled\\.small\\.r|triangle\\.filled\\.small\\.t|triangle\\.filled\\.t|triangle\\.filled\\.t\\.small|triangle\\.filled\\.tl|triangle\\.filled\\.tr|triangle\\.l|triangle\\.l\\.filled|triangle\\.l\\.filled\\.small|triangle\\.l\\.small|triangle\\.l\\.small\\.filled|triangle\\.l\\.small\\.stroked|triangle\\.l\\.stroked|triangle\\.l\\.stroked\\.small|triangle\\.nested|triangle\\.nested\\.stroked|triangle\\.r|triangle\\.r\\.filled|triangle\\.r\\.filled\\.small|triangle\\.r\\.small|triangle\\.r\\.small\\.filled|triangle\\.r\\.small\\.stroked|triangle\\.r\\.stroked|triangle\\.r\\.stroked\\.small|triangle\\.rounded|triangle\\.rounded\\.stroked|triangle\\.small|triangle\\.small\\.b|triangle\\.small\\.b\\.filled|triangle\\.small\\.b\\.stroked|triangle\\.small\\.filled|triangle\\.small\\.filled\\.b|triangle\\.small\\.filled\\.l|triangle\\.small\\.filled\\.r|triangle\\.small\\.filled\\.t|triangle\\.small\\.l|triangle\\.small\\.l\\.filled|triangle\\.small\\.l\\.stroked|triangle\\.small\\.r|triangle\\.small\\.r\\.filled|triangle\\.small\\.r\\.stroked|triangle\\.small\\.stroked|triangle\\.small\\.stroked\\.b|triangle\\.small\\.stroked\\.l|triangle\\.small\\.stroked\\.r|triangle\\.small\\.stroked\\.t|triangle\\.small\\.t|triangle\\.small\\.t\\.filled|triangle\\.small\\.t\\.stroked|triangle\\.stroked|triangle\\.stroked\\.b|triangle\\.stroked\\.b\\.small|triangle\\.stroked\\.bl|triangle\\.stroked\\.br|triangle\\.stroked\\.dot|triangle\\.stroked\\.l|triangle\\.stroked\\.l\\.small|triangle\\.stroked\\.nested|triangle\\.stroked\\.r|triangle\\.stroked\\.r\\.small|triangle\\.stroked\\.rounded|triangle\\.stroked\\.small|triangle\\.stroked\\.small\\.b|triangle\\.stroked\\.small\\.l|triangle\\.stroked\\.small\\.r|triangle\\.stroked\\.small\\.t|triangle\\.stroked\\.t|triangle\\.stroked\\.t\\.small|triangle\\.stroked\\.tl|triangle\\.stroked\\.tr|triangle\\.t|triangle\\.t\\.filled|triangle\\.t\\.filled\\.small|triangle\\.t\\.small|triangle\\.t\\.small\\.filled|triangle\\.t\\.small\\.stroked|triangle\\.t\\.stroked|triangle\\.t\\.stroked\\.small|triangle\\.tl|triangle\\.tl\\.filled|triangle\\.tl\\.stroked|triangle\\.tr|triangle\\.tr\\.filled|triangle\\.tr\\.stroked|union\\.arrow|union\\.big|union\\.big\\.dot|union\\.big\\.plus|union\\.big\\.sq|union\\.dot|union\\.dot\\.big|union\\.double|union\\.double\\.sq|union\\.minus|union\\.or|union\\.plus|union\\.plus\\.big|union\\.sq|union\\.sq\\.big|union\\.sq\\.double|uranus\\.alt|xor\\.big)$"))
  (#set! priority 102)
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set-conceal! @typ_math_symbol "conceal")
  )

; Math operators and symbols
(((ident) @typ_math_symbol
  (#match? @typ_math_symbol "^(AA|Alpha|BB|Beta|CC|DD|Digamma|EE|Epsilon|Eta|FF|GG|HH|II|Im|Iota|JJ|KK|Kai|Kappa|LL|MM|Mu|NN|Nu|OO|Omicron|PP|QQ|RR|Re|Rho|SS|Sha|TT|Tau|UU|VV|WW|XX|YY|ZZ|Zeta|acute|afghani|alef|aleph|amp|and|angle|angstrom|angzarr|approx|arrow|arrowhead|arrows|ast|asymp|at|backslash|bag|baht|ballot|bar|because|bet|beth|bitcoin|bot|brace|bracket|breve|bullet|caret|caron|cc|cedi|ceil|cent|checkmark|chevron|circle|co|colon|comma|complement|compose|convolve|copyleft|copyright|corner|crossmark|currency|dagger|dalet|daleth|dash|degree|diaer|diameter|diamond|die|diff|digamma|div|divides|dollar|dong|dorome|dot|dotless|dots|dram|earth|ell|ellipse|emptyset|eq|equiv|errorbar|euro|excl|exists|fence|flat|floor|floral|forall|forces|franc|frown|gimel|gimmel|gradient|grave|gt|guarani|harpoon|harpoons|hash|hat|hexa|hourglass|hryvnia|hyph|image|in|infinity|integral|inter|interleave|interrobang|join|jupiter|kai|kip|laplace|lari|lat|lira|lozenge|lrm|lt|macron|maltese|manat|mapsto|mars|mercury|minus|miny|models|multimap|mustache|naira|natural|neptune|not|note|nothing|numero|omicron|oo|or|original|parallel|parallelogram|paren|partial|pataca|penta|percent|permille|permyriad|perp|peso|pilcrow|planck|plus|pound|power|prec|prime|product|prop|qed|quest|quote|ratio|rect|refmark|rest|riel|rlm|ruble|rupee|saturn|sect|section|semi|sha|sharp|shekel|shell|shin|slash|smash|smile|smt|som|space|square|star|subset|succ|suit|sum|sun|supset|tack|taka|taman|tenge|therefore|tilde|times|tiny|togrog|top|trademark|triangle|union|uranus|venus|without|wj|won|wreath|xor|yen|yuan|zwj|zwnj|zws)$"))
  (#has-ancestor? @typ_math_symbol math formula)
  ; (#not-has-ancestor? @typ_math_symbol call)
  (#set! priority 101)
  (#set-conceal! @typ_math_symbol "conceal"))

]]

M.conceal_font = [[
; Typst font style conceals
; Bold math symbols
(call
  item: (ident) @typ_font_name
  (#any-of? @typ_font_name
    "bold" "italic" "cal" "script" "bb" "sans" "mono" "frak" "double" "upright" )
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#match? @font_letter "^[a-zA-Z]$")
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal ""))

; overline conceal for ident
(call
  item: (_) @typ_font_name
  (#any-of? @typ_font_name "overline" "tilde" "hat" "dot" "dot.double")
  (#set! @typ_font_name conceal "")
  "(" @left_paren
  (#set! @left_paren conceal "")
  (formula) @font_letter
  (#match? @font_letter "^([a-zA-Z]|alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|partial|chi|psi|omega|varepsilon|vartheta|varpi|varrho|varsigma|varphi|digamma|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega|Varepsilon|Vartheta|Varpi|Varrho|Varsigma|Varphi)$")
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
  (#match? @font_letter "diff")
  (#set-font! @font_letter @typ_font_name "font")
  ")" @right_paren
  (#set! @right_paren conceal "")
  (#set! priority 102))

; Math function calls with special symbols
(call
  item: (ident) @typ_math_font
  (#any-of? @typ_math_font "dif")
  ; (#has-ancestor? @func math formula)
  (#set! conceal ""))

(((ident) @typ_math_font
  (#any-of? @typ_math_font "dif"))
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set-conceal! @typ_math_font "conceal"))

; Script functions like upright, script, etc.
(call
  item: (ident) @func
  (#any-of? @func "upright" "italic" "script" "mono" "sans")
  (#has-ancestor? @func math formula)
  (#set! conceal ""))

]]

M.conceal_phy = [[
; Typst physics symbol conceals
; Physics constants and symbols
(call
  item: (ident) @typ_phy_symbol
  (#match? @typ_phy_symbol "^(hbar|planck|boltzmann|avogadro|gas|electron|proton|neutron|muon|tau|charge|mass|energy|momentum|angular|spin|magnetic|electric|permittivity|permeability|speed|light|gravity|acceleration|force|pressure|temperature|entropy|enthalpy|helmholtz|gibbs)$")
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set! priority 98)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Physics units and quantities
((ident) @typ_phy_symbol
  (#match? @typ_phy_symbol "^(hbar|planck|boltzmann|avogadro|electron|proton|neutron|speed|light|gravity|charge|mass|energy|momentum|angular|spin|magnetic|electric|force|pressure|temperature|entropy|enthalpy|helmholtz|gibbs)$")
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

M.conceal_greek = [[
; Typst Greek letter conceals
; Greek letters as function calls
(call
  item: ((ident) @typ_greek_symbol
    (#match? @typ_greek_symbol "^((alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|nabla)|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Chi|Psi|Omega)$"))
  (#set! priority 102)
  (#set-conceal! @typ_greek_symbol "conceal"))
  ; (#has-ancestor? @conceal math formula)

; (#lua_func! @conceal "conceal"))
; Greek letters as direct identifiers
(((ident) @typ_greek_symbol
  (#match? @typ_greek_symbol "^(alpha|beta|gamma|delta|epsilon|varepsilon|zeta|eta|theta|vartheta|iota|kappa|lambda|mu|nu|xi|pi|varpi|rho|varrho|sigma|varsigma|tau|upsilon|phi|varphi|chi|psi|omega|nabla|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Chi|Psi|Omega)$"))
  (#set! priority 102)
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#set-conceal! @typ_greek_symbol "conceal"))

]]

return M
