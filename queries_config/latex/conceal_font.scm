(generic_command
  command: (command_name) @conceal
  (#any-of? @conceal "\\emph" "\\mathit" "\\textit" "\\mathbf" "\\textbf" "\\mathbb" "\\mathcal" "\\mathfrak" "\\mathscr" "\\mathsf" "\\mathrm")
  (#set! conceal ""))

((generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    (_)
    "}" @right_paren))
  (#any-of? @tex_font_name "\\emph" "\\mathit" "\\textit" "\\mathbf" "\\textbf" "\\mathbb" "\\mathcal" "\\mathfrak" "\\mathscr" "\\mathsf" "\\mathrm")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

((generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    (text
      word: (word) @font_letter)
    "}" @right_paren))
  (#any-of? @tex_font_name "\\mathbb" "\\mathcal" "\\mathfrak" "\\mathscr" "\\mathsf" "\\mathrm")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  (#match? @font_letter "^[a-zA-Z]$")
  (#set-font! @font_letter @tex_font_name))

((generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    (_) @font_letter
    "}" @right_paren))
  (#any-of? @tex_font_name "\\bar" "\\widetilde" "\\hat" "\\dot" "\\ddot")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  (#match? @font_letter "^([a-zA-Z]|\\\\(alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|varepsilon|vartheta|varpi|varrho|varsigma|varphi|digamma|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega|Varepsilon|Vartheta|Varpi|Varrho|Varsigma|Varphi))$")
  (#set-font! @font_letter @tex_font_name))
