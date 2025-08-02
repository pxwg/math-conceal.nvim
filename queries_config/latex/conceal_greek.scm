; greek conceal
(generic_command
  command: ((command_name) @tex_greek
    (#match? @tex_greek "^\\\\(varalpha|varbeta|vargamma|vardelta|varepsilon|varzeta|vareta|vartheta|variota|varkappa|varlambda|varmu|varnu|varxi|varpi|varrho|varsigma|vartau|varupsilon|varphi|varchi|varpsi|varomega|alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega)$"))
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))

(generic_command
  command: ((command_name) @tex_greek
    (#match? @tex_greek "^\\\\(Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Chi|Psi|Omega)$"))
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))
