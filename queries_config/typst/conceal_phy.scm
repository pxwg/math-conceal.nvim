; Typst physics symbol conceals

; Physics constants and symbols
(call
  item: (ident) @conceal
  (#any-of? @conceal
   "hbar" "planck" "boltzmann" "avogadro" "gas" "electron" "proton"
   "neutron" "muon" "tau" "charge" "mass" "energy" "momentum"
   "angular" "spin" "magnetic" "electric" "permittivity" "permeability"
   "speed" "light" "gravity" "acceleration" "force" "pressure"
   "temperature" "entropy" "enthalpy" "helmholtz" "gibbs")
  ; (#has-ancestor? @conceal math formula)
  (#lua_func! @conceal "conceal"))

; Physics units and quantities
((ident) @conceal
(#any-of? @conceal
 "hbar" "planck" "boltzmann" "avogadro" "electron" "proton" "neutron"
 "speed" "light" "gravity" "charge" "mass" "energy" "momentum"
 "angular" "spin" "magnetic" "electric" "force" "pressure"
 "temperature" "entropy" "enthalpy" "helmholtz" "gibbs")
; (#has-ancestor? @conceal math formula)
(#lua_func! @conceal "conceal"))

; Vector and tensor notation
((ident) @func
(#any-of? @func "vec" "hat" "tilde" "bar" "dot" "ddot" "dddot")
; (#has-ancestor? @func math formula)
(#set! conceal ""))

; Derivatives and differentials
 ((ident) @func
 (#any-of? @func "diff" "pdiff" "grad" "div" "curl" "laplacian")
 ; (#has-ancestor? @func math formula)
 (#lua_func! @func "conceal"))

; Physics operators
((ident) @func
(#any-of? @func "expval" "mel" "bra" "ket" "braket" "ketbra" "op")
; (#has-ancestor? @func math formula)
(#lua_func! @func "conceal"))

