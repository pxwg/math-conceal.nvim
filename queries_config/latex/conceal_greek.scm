; greek conceal
(generic_command
  command: ((command_name) @tex_greek_symbol
    (#any-of? @tex_greek_symbol
      "\\alpha" "\\beta" "\\gamma" "\\delta" "\\epsilon" "\\varepsilon" "\\zeta" "\\eta" "\\theta"
      "\\vartheta" "\\iota" "\\kappa" "\\lambda" "\\mu" "\\nu" "\\xi" "\\pi" "\\varpi" "\\rho"
      "\\varrho" "\\sigma" "\\varsigma" "\\tau" "\\upsilon" "\\phi" "\\varphi" "\\chi" "\\psi"
      "\\omega" "\\Gamma" "\\Delta" "\\Theta" "\\Lambda" "\\Xi" "\\Pi" "\\Sigma" "\\Upsilon" "\\Phi"
      "\\Chi" "\\Psi" "\\Omega"))
  (#has-ancestor? @tex_greek_symbol math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @tex_greek_symbol label_definition text_mode)
  (#set-conceal! @tex_greek_symbol "conceal"))
