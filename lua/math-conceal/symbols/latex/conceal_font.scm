(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#any-of? @tex_font_name
    "\\textbf" "\\textit" "\\textlf" "\\textmd" "\\textrm" "\\textsc" "\\textsl" "\\textsf"
    "\\texttc" "\\texttt" "\\textulc" "\\textup" "\\textnormal" "\\emph" "\\rmfamily" "\\sffamily"
    "\\ttfamily" "\\itshape" "\\scshape" "\\slshape" "\\upshape" "\\bfseries" "\\mdseries")
  (#not-has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#any-of? @tex_font_name
    "\\textbf" "\\textit" "\\textlf" "\\textmd" "\\textrm" "\\textsc" "\\textsl" "\\textsf"
    "\\texttc" "\\texttt" "\\textulc" "\\textup" "\\textnormal" "\\emph" "\\rmfamily" "\\sffamily"
    "\\ttfamily" "\\itshape" "\\scshape" "\\slshape" "\\upshape" "\\bfseries" "\\mdseries")
  (#has-ancestor? @tex_font_name text_mode)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  (#any-of? @tex_font_name
    "\\tiny" "\\scriptsize" "\\footnotesize" "\\normalsize" "\\small" "\\large" "\\Large" "\\LARGE"
    "\\huge" "\\Huge" "\\normalfont")
  (#not-has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#set! @tex_font_name conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  (#any-of? @tex_font_name
    "\\tiny" "\\scriptsize" "\\footnotesize" "\\normalsize" "\\small" "\\large" "\\Large" "\\LARGE"
    "\\huge" "\\Huge" "\\normalfont")
  (#has-ancestor? @tex_font_name text_mode)
  (#set! conceal ""))

(text_mode
  command: "\\text" @tex_font_name
  content: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

(text_mode
  command: [
    "\\intertext"
    "\\shortintertext"
  ] @tex_font_name
  content: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#has-ancestor? @tex_font_name math_environment)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#any-of? @tex_font_name
    "\\mathrm" "\\mathtt" "\\mathsf" "\\mathnormal" "\\mathbf" "\\mathit" "\\mathcal" "\\mathbfit"
    "\\mathbb" "\\mathfrak" "\\mathscr" "\\mathds" "\\mathbbm" "\\mathbbb")
  (#has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @tex_font_name text_mode)
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
  (#has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @tex_font_name text_mode)
  (#any-of? @tex_font_name "\\mathbb" "\\mathcal" "\\mathfrak" "\\mathscr" "\\mathsf" "\\mathrm")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  ; Regex removed - Rust hash table will filter valid font letters
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
  ; Regex removed - Rust hash table will filter valid characters/greek letters
  (#set-font! @font_letter @tex_font_name))
