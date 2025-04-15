; greek conceal
(generic_command
  command: ((command_name) @conceal 
  (#any-of? @conceal 
   "\\alpha" "\\beta" "\\gamma" "\\delta"
   "\\epsilon" "\\varepsilon" "\\zeta" "\\eta"
   "\\theta" "\\vartheta" "\\iota" "\\kappa"
   "\\lambda" "\\mu" "\\nu" "\\xi"
   "\\pi" "\\varpi" "\\rho" "\\varrho"
   "\\sigma" "\\varsigma" "\\tau" "\\upsilon"
   "\\phi" "\\varphi" "\\chi" "\\psi"
   "\\omega" "\\Gamma" "\\Delta" "\\Theta"
   "\\Lambda" "\\Xi" "\\Pi" "\\Sigma"
   "\\Upsilon" "\\Phi" "\\Chi" "\\Psi"
   "\\Omega"))
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#lua_func! @conceal "conceal"))
