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

; (((ident) @typ_math_symbol
; (#any-of? @typ_math_symbol
; (#lua_func! @typ_math_symbol "conceal"))
; Math operators and symbols
(((ident) @typ_math_symbol
  (#any-of? @typ_math_symbol
    "sum" "sqrt" "product" "integral" "nabla" "partial" "infinity" "emptyset" "aleph" "subset"
    "superset" "union" "intersection" "in" "notin" "element" "forall" "exists" "neg" "and" "or"
    "implies" "iff" "equiv" "approx" "neq" "leq" "geq" "ll" "gg" "pm" "mp" "times" "div" "cdot"
    "bullet" "circ" "ast" "cap" "cup" "sqcap" "sqcup" "vee" "wedge" "oplus" "ominus" "otimes"
    "oslash" "odot" "parallel" "perp" "angle" "triangle" "square" "diamond" "star" "dagger"
    "ddagger" "sharp" "flat" "natural" "clubs" "diamonds" "hearts" "spades" "dif" "diff" "quad"
    "angle" "amp" "at" "backslash" "co" "colon" "comma" "dagger" "dot" "dots" "excl" "quest"
    "interrobang" "hash" "hyph" "percent" "copyright" "permille" "pilcrow" "section" "semi" "slash"
    "acute" "breve" "caret" "caron" "hat" "diaer" "grave" "macron" "prime" "plus" "minus" "div"
    "times" "ratio" "eq" "gt" "lt" "approx" "prec" "succ" "equiv" "prop" "emptyset" "nothing"
    "without" "complement" "in" "subset" "supset" "union" "sect" "infinity" "oo" "diff" "nabla"
    "sum" "product" "integral" "laplace" "forall" "exists" "top" "bot" "not" "and" "or" "xor"
    "models" "therefore" "because" "qed" "compose" "convolve" "multimap" "divides" "wreath"
    "parallel" "perp" "diameter" "join" "degree" "smash" "bitcoin" "dollar" "euro" "franc" "lira"
    "peso" "pound" "ruble" "rupee" "won" "yen" "ballot" "checkmark" "floral" "refmark" "servicemark"
    "maltese" "bullet" "alpha" "beta" "chi" "delta" "epsilon" "eta" "gamma" "iota" "kai" "kappa"
    "lambda" "mu" "nu" "ohm" "omega" "omicron" "phi" "pi" "psi" "rho" "sigma" "tau" "theta"
    "upsilon" "xi" "zeta" "Alpha" "Beta" "Chi" "Delta" "Epsilon" "Eta" "Gamma" "Iota" "Kai" "Kappa"
    "Lambda" "Mu" "Nu" "Omega" "Omicron" "Phi" "Pi" "Psi" "Rho" "Sigma" "Tau" "Theta" "Upsilon" "Xi"
    "Zeta" "aleph" "alef" "beth" "bet" "gimmel" "gimel" "shin" "AA" "BB" "CC" "DD" "EE" "FF" "GG"
    "HH" "II" "JJ" "KK" "LL" "MM" "NN" "OO" "PP" "QQ" "RR" "SS" "TT" "UU" "VV" "WW" "XX" "YY" "ZZ"
    "ell" "planck" "angstrom" "kelvin" "Re" "Im"))
  (#lua_func! @typ_math_symbol "conceal"))

(((field) @typ_math_symbol
  (#any-of? @typ_math_symbol
    "paren.l" "paren.r" "paren.t" "paren.b" "brace.l" "brace.r" "brace.t" "brace.b" "bracket.l"
    "bracket.l.double" "bracket.r" "bracket.r.double" "bracket.t" "bracket.b" "turtle.l" "turtle.r"
    "turtle.t" "turtle.b" "bar.v" "bar.v.double" "bar.v.triple" "bar.v.broken" "bar.v.circle"
    "bar.h" "fence.l" "fence.l.double" "fence.r" "fence.r.double" "fence.dotted" "angle.l" "angle.r"
    "angle.l.double" "angle.r.double" "angle.acute" "angle.arc" "angle.arc.rev" "angle.rev"
    "angle.right" "angle.right.rev" "angle.right.arc" "angle.right.dot" "angle.right.sq"
    "angle.spatial" "angle.spheric" "angle.spheric.rev" "angle.spheric.top" "amp.inv" "ast.op"
    "ast.basic" "ast.low" "ast.double" "ast.triple" "ast.small" "ast.circle" "ast.square"
    "backslash.circle" "backslash.not" "colon.eq" "colon.double.eq" "dagger.double" "dash.en"
    "dash.em" "dash.fig" "dash.wave" "dash.colon" "dash.circle" "dash.wave.double" "dot.op"
    "dot.basic" "dot.c" "dot.circle" "dot.circle.big" "dot.square" "dot.double" "excl.double"
    "excl.inv" "excl.quest" "quest.double" "quest.excl" "quest.inv" "hyph.minus" "hyph.nobreak"
    "hyph.point" "hyph.soft" "copyright.sound" "pilcrow.rev" "semi.rev" "slash.double"
    "slash.triple" "slash.big" "dots.h.c" "dots.c" "dots.h" "dots.v" "dots.down" "dots.up"
    "tilde.op" "tilde.basic" "tilde.eq" "tilde.eq.not" "tilde.eq.rev" "tilde.equiv"
    "tilde.equiv.not" "tilde.nequiv" "tilde.not" "tilde.rev" "tilde.rev.equiv" "tilde.triple"
    "acute.double" "quote.double" "quote.l.double" "quote.l.single" "quote.r.double"
    "quote.r.single" "quote.angle.l.double" "quote.angle.l.single" "quote.angle.r.double"
    "quote.angle.r.single" "quote.high.double" "quote.high.single" "quote.low.double"
    "quote.low.single" "prime.rev" "prime.double" "prime.double.rev" "prime.triple"
    "prime.triple.rev" "prime.quad" "plus.circle" "plus.circle.arrow" "plus.circle.big" "plus.dot"
    "plus.minus" "plus.small" "plus.square" "plus.triangle" "minus.circle" "minus.dot" "minus.plus"
    "minus.square" "minus.tilde" "minus.triangle" "div.circle" "times.big" "times.circle"
    "times.circle.big" "times.div" "times.three.l" "times.three.r" "times.l" "times.r"
    "times.square" "times.triangle" "eq.star" "eq.circle" "eq.colon" "eq.def" "eq.delta" "eq.equi"
    "eq.est" "eq.gt" "eq.lt" "eq.m" "eq.not" "eq.prec" "eq.quest" "eq.small" "eq.succ" "eq.triple"
    "eq.quad" "gt.circle" "gt.curly" "gt.curly.approx" "gt.curly.double" "gt.curly.eq"
    "gt.curly.eq.not" "gt.curly.equiv" "gt.curly.napprox" "gt.curly.nequiv" "gt.curly.not"
    "gt.curly.ntilde" "gt.curly.tilde" "gt.dot" "gt.double" "gt.eq" "gt.eq.slant" "gt.eq.lt"
    "gt.eq.not" "gt.equiv" "gt.lt" "gt.lt.not" "gt.nequiv" "gt.not" "gt.ntilde" "gt.small"
    "gt.tilde" "gt.tilde.not" "gt.tri" "gt.tri.eq" "gt.tri.eq.not" "gt.tri.not" "gt.triple"
    "gt.triple.nested" "lt.circle" "lt.curly" "lt.curly.approx" "lt.curly.double" "lt.curly.eq"
    "lt.curly.eq.not" "lt.curly.equiv" "lt.curly.napprox" "lt.curly.nequiv" "lt.curly.not"
    "lt.curly.ntilde" "lt.curly.tilde" "lt.dot" "lt.double" "lt.eq" "lt.eq.slant" "lt.eq.gt"
    "lt.eq.not" "lt.equiv" "lt.gt" "lt.gt.not" "lt.nequiv" "lt.not" "lt.ntilde" "lt.small"
    "lt.tilde" "lt.tilde.not" "lt.tri" "lt.tri.eq" "lt.tri.eq.not" "lt.tri.not" "lt.triple"
    "lt.triple.nested" "approx.eq" "approx.not" "prec.approx" "prec.double" "prec.eq" "prec.eq.not"
    "prec.equiv" "prec.napprox" "prec.nequiv" "prec.not" "prec.ntilde" "prec.tilde" "succ.approx"
    "succ.double" "succ.eq" "succ.eq.not" "succ.equiv" "succ.napprox" "succ.nequiv" "succ.not"
    "succ.ntilde" "succ.tilde" "equiv.not" "emptyset.rev" "nothing.rev" "in.not" "in.rev"
    "in.rev.not" "in.rev.small" "in.small" "subset.dot" "subset.double" "subset.eq" "subset.eq.not"
    "subset.eq.sq" "subset.eq.sq.not" "subset.neq" "subset.not" "subset.sq" "subset.sq.neq"
    "supset.dot" "supset.double" "supset.eq" "supset.eq.not" "supset.eq.sq" "supset.eq.sq.not"
    "supset.neq" "supset.not" "supset.sq" "supset.sq.neq" "union.arrow" "union.big" "union.dot"
    "union.dot.big" "union.double" "union.minus" "union.or" "union.plus" "union.plus.big" "union.sq"
    "union.sq.big" "union.sq.double" "sect.and" "sect.big" "sect.dot" "sect.double" "sect.sq"
    "sect.sq.big" "sect.sq.double" "sum.integral" "product.co" "integral.arrow.hook" "arrow.hook"
    "integral.ccw" "integral.cont" "integral.cont.ccw" "integral.cont.cw" "integral.cw"
    "integral.double" "integral.quad" "integral.sect" "integral.square" "integral.surf"
    "integral.times" "integral.triple" "integral.union" "integral.vol" "exists.not" "and.big"
    "and.curly" "and.dot" "and.double" "or.big" "or.curly" "or.dot" "or.double" "xor.big"
    "divides.not" "parallel.circle" "parallel.not" "perp.circle" "join.r" "join.l" "join.l.r"
    "degree.c" "degree.f" "ballot.x" "checkmark.light" "floral.l" "floral.r" "notes.up" "notes.down"
    "suit.club" "suit.diamond" "suit.heart" "suit.spade" "circle.stroked" "circle.stroked.tiny"
    "circle.stroked.small" "circle.stroked.big" "circle.filled" "circle.filled.tiny"
    "circle.filled.small" "circle.filled.big" "circle.dotted" "circle.nested" "ellipse.stroked.h"
    "ellipse.stroked.v" "ellipse.filled.h" "ellipse.filled.v" "triangle.stroked.r"
    "triangle.stroked.l" "triangle.stroked.t" "triangle.stroked.b" "triangle.stroked.bl"
    "triangle.stroked.br" "triangle.stroked.tl" "triangle.stroked.tr" "triangle.stroked.small.r"
    "triangle.stroked.small.b" "triangle.stroked.small.l" "triangle.stroked.small.t"
    "triangle.stroked.rounded" "triangle.stroked.nested" "triangle.stroked.dot" "triangle.filled.r"
    "triangle.filled.l" "triangle.filled.t" "triangle.filled.b" "triangle.filled.bl"
    "triangle.filled.br" "triangle.filled.tl" "triangle.filled.tr" "triangle.filled.small.r"
    "triangle.filled.small.b" "triangle.filled.small.l" "triangle.filled.small.t" "square.stroked"
    "square.stroked.tiny" "square.stroked.small" "square.stroked.medium" "square.stroked.big"
    "square.stroked.dotted" "square.stroked.rounded" "square.filled" "square.filled.tiny"
    "square.filled.small" "square.filled.medium" "square.filled.big" "rect.stroked.h"
    "rect.stroked.v" "rect.filled.h" "rect.filled.v" "penta.stroked" "penta.filled" "hexa.stroked"
    "hexa.filled" "diamond.stroked" "diamond.stroked.small" "diamond.stroked.medium"
    "diamond.stroked.dot" "diamond.filled" "diamond.filled.medium" "diamond.filled.small"
    "lozenge.stroked" "lozenge.stroked.small" "lozenge.stroked.medium" "lozenge.filled"
    "lozenge.filled.small" "lozenge.filled.medium" "star.op" "star.stroked" "star.filled" "arrow.r"
    "arrow.r.long.bar" "arrow.r.bar" "arrow.r.curve" "arrow.r.dashed" "arrow.r.dotted"
    "arrow.r.double" "arrow.r.double.bar" "arrow.r.double.long" "arrow.r.double.long.bar"
    "arrow.r.double.not" "arrow.r.filled" "arrow.r.hook" "arrow.r.long" "arrow.r.long.squiggly"
    "arrow.r.loop" "arrow.r.not" "arrow.r.quad" "arrow.r.squiggly" "arrow.r.stop" "arrow.r.stroked"
    "arrow.r.tail" "arrow.r.triple" "arrow.r.twohead.bar" "arrow.r.twohead" "arrow.r.wave" "arrow.l"
    "arrow.l.bar" "arrow.l.curve" "arrow.l.dashed" "arrow.l.dotted" "arrow.l.double"
    "arrow.l.double.bar" "arrow.l.double.long" "arrow.l.double.long.bar" "arrow.l.double.not"
    "arrow.l.filled" "arrow.l.hook" "arrow.l.long" "arrow.l.long.bar" "arrow.l.long.squiggly"
    "arrow.l.loop" "arrow.l.not" "arrow.l.quad" "arrow.l.squiggly" "arrow.l.stop" "arrow.l.stroked"
    "arrow.l.tail" "arrow.l.triple" "arrow.l.twohead.bar" "arrow.l.twohead" "arrow.l.wave" "arrow.t"
    "arrow.t.bar" "arrow.t.curve" "arrow.t.dashed" "arrow.t.double" "arrow.t.filled" "arrow.t.quad"
    "arrow.t.stop" "arrow.t.stroked" "arrow.t.triple" "arrow.t.twohead" "arrow.b" "arrow.b.bar"
    "arrow.b.curve" "arrow.b.dashed" "arrow.b.double" "arrow.b.filled" "arrow.b.quad" "arrow.b.stop"
    "arrow.b.stroked" "arrow.b.triple" "arrow.b.twohead" "arrow.l.r" "arrow.l.r.double"
    "arrow.l.r.double.long" "arrow.l.r.double.not" "arrow.l.r.filled" "arrow.l.r.long"
    "arrow.l.r.not" "arrow.l.r.stroked" "arrow.l.r.wave" "arrow.t.b" "arrow.t.b.double"
    "arrow.t.b.filled" "arrow.t.b.stroked" "arrow.tr" "arrow.tr.double" "arrow.tr.filled"
    "arrow.tr.hook" "arrow.tr.stroked" "arrow.br" "arrow.br.double" "arrow.br.filled"
    "arrow.br.hook" "arrow.br.stroked" "arrow.tl" "arrow.tl.double" "arrow.tl.filled"
    "arrow.tl.hook" "arrow.tl.stroked" "arrow.bl" "arrow.bl.double" "arrow.bl.filled"
    "arrow.bl.hook" "arrow.bl.stroked" "arrow.tl.br" "arrow.tr.bl" "arrow.ccw" "arrow.ccw.half"
    "arrow.cw" "arrow.cw.half" "arrow.zigzag" "arrows.rr" "arrows.ll" "arrows.tt" "arrows.bb"
    "arrows.lr" "arrows.lr.stop" "arrows.rl" "arrows.tb" "arrows.bt" "arrows.rrr" "arrows.lll"
    "arrowhead.t" "arrowhead.b" "harpoon.rt" "harpoon.rt.bar" "harpoon.rt.stop" "harpoon.rb"
    "harpoon.rb.bar" "harpoon.rb.stop" "harpoon.lt" "harpoon.lt.bar" "harpoon.lt.stop" "harpoon.lb"
    "harpoon.lb.bar" "harpoon.lb.stop" "harpoon.tl" "harpoon.tl.bar" "harpoon.tl.stop" "harpoon.tr"
    "harpoon.tr.bar" "harpoon.tr.stop" "harpoon.bl" "harpoon.bl.bar" "harpoon.bl.stop" "harpoon.br"
    "harpoon.br.bar" "harpoon.br.stop" "harpoon.lt.rt" "harpoon.lb.rb" "harpoon.lb.rt"
    "harpoon.lt.rb" "harpoon.tl.bl" "harpoon.tr.br" "harpoon.tl.br" "harpoon.tr.bl" "harpoons.rtrb"
    "harpoons.blbr" "harpoons.bltr" "harpoons.lbrb" "harpoons.ltlb" "harpoons.ltrb" "harpoons.ltrt"
    "harpoons.rblb" "harpoons.rtlb" "harpoons.rtlt" "harpoons.tlbr" "harpoons.tltr" "tack.r"
    "tack.r.not" "tack.r.long" "tack.r.short" "tack.r.double" "tack.r.double.not" "tack.l"
    "tack.l.long" "tack.l.short" "tack.l.double" "tack.t" "tack.t.big" "tack.t.double"
    "tack.t.short" "tack.b" "tack.b.big" "tack.b.double" "tack.b.short" "tack.l.r" "beta.alt"
    "epsilon.alt" "kappa.alt" "ohm.inv" "phi.alt" "pi.alt" "rho.alt" "sigma.alt" "theta.alt"
    "planck.reduce" "dotless.i" "dotless.j"))
  (#lua_func! @typ_math_symbol "conceal")
  (#set! priority 1000))

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
