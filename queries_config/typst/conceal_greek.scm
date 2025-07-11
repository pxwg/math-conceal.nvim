; Typst Greek letter conceals

; Greek letters as function calls
(call
  item: ((ident) @conceal
  (#any-of? @conceal
   "alpha" "beta" "gamma" "delta" "epsilon" "varepsilon" "zeta" "eta" 
   "theta" "vartheta" "iota" "kappa" "lambda" "mu" "nu" "xi" 
   "pi" "varpi" "rho" "varrho" "sigma" "varsigma" "tau" "upsilon" 
   "phi" "varphi" "chi" "psi" "omega" "nabla"
   "Gamma" "Delta" "Theta" "Lambda" "Xi" "Pi" "Sigma" "Upsilon" 
   "Phi" "Chi" "Psi" "Omega"))
  ; (#has-ancestor? @conceal math formula)
  (#set! conceal ""))
  ; (#lua_func! @conceal "conceal"))

; Greek letters as direct identifiers  
(((ident) @conceal
(#any-of? @conceal
 "alpha" "beta" "gamma" "delta" "epsilon" "varepsilon" "zeta" "eta"
 "theta" "vartheta" "iota" "kappa" "lambda" "mu" "nu" "xi"
 "pi" "varpi" "rho" "varrho" "sigma" "varsigma" "tau" "upsilon"
 "phi" "varphi" "chi" "psi" "omega" "nabla"
 "Gamma" "Delta" "Theta" "Lambda" "Xi" "Pi" "Sigma" "Upsilon"
 "Phi" "Chi" "Psi" "Omega"))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @conceal "conceal"))

