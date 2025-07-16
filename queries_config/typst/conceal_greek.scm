; Typst Greek letter conceals
; Greek letters as function calls
(call
  item: ((ident) @typ_greek_symbol
    (#any-of? @typ_greek_symbol
      "alpha" "beta" "gamma" "delta" "epsilon" "varepsilon" "zeta" "eta" "theta" "vartheta" "iota"
      "kappa" "lambda" "mu" "nu" "xi" "pi" "varpi" "rho" "varrho" "sigma" "varsigma" "tau" "upsilon"
      "phi" "varphi" "chi" "psi" "omega" "nabla" "Gamma" "Delta" "Theta" "Lambda" "Xi" "Pi" "Sigma"
      "Upsilon" "Phi" "Chi" "Psi" "Omega"))
  ; (#has-ancestor? @conceal math formula)
  (#set! conceal ""))

; (#lua_func! @conceal "conceal"))
; Greek letters as direct identifiers
(((ident) @typ_greek_symbol
  (#any-of? @typ_greek_symbol
    "alpha" "beta" "gamma" "delta" "epsilon" "varepsilon" "zeta" "eta" "theta" "vartheta" "iota"
    "kappa" "lambda" "mu" "nu" "xi" "pi" "varpi" "rho" "varrho" "sigma" "varsigma" "tau" "upsilon"
    "phi" "varphi" "chi" "psi" "omega" "nabla" "Gamma" "Delta" "Theta" "Lambda" "Xi" "Pi" "Sigma"
    "Upsilon" "Phi" "Chi" "Psi" "Omega"))
  ; (#has-ancestor? @conceal math formula)
  ; (#set! @conceal "m"))
  (#lua_func! @typ_greek_symbol "conceal"))
