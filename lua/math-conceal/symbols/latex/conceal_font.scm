(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#any-of? @tex_font_name
    "\\bfseries" "\\emph" "\\itshape" "\\mdseries" "\\rmfamily" "\\scshape" "\\sffamily" "\\slshape"
    "\\textbf" "\\textit" "\\textlf" "\\textmd" "\\textnormal" "\\textrm" "\\textsc" "\\textsf"
    "\\textsl" "\\texttc" "\\texttt" "\\textulc" "\\textup" "\\ttfamily" "\\upshape")
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
    "\\bfseries" "\\emph" "\\itshape" "\\mdseries" "\\rmfamily" "\\scshape" "\\sffamily" "\\slshape"
    "\\textbf" "\\textit" "\\textlf" "\\textmd" "\\textnormal" "\\textrm" "\\textsc" "\\textsf"
    "\\textsl" "\\texttc" "\\texttt" "\\textulc" "\\textup" "\\ttfamily" "\\upshape")
  (#has-ancestor? @tex_font_name text_mode)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  (#any-of? @tex_font_name
    "\\Huge" "\\LARGE" "\\Large" "\\footnotesize" "\\huge" "\\large" "\\normalfont" "\\normalsize"
    "\\scriptsize" "\\small" "\\tiny")
  (#not-has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#set! @tex_font_name conceal ""))

(generic_command
  command: (command_name) @tex_font_name
  (#any-of? @tex_font_name
    "\\Huge" "\\LARGE" "\\Large" "\\footnotesize" "\\huge" "\\large" "\\normalfont" "\\normalsize"
    "\\scriptsize" "\\small" "\\tiny")
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

; full math-font commans list. Work with pdflatex and unicode-math
(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    [
      "{" @left_paren
      "}" @right_paren
    ])
  (#any-of? @tex_font_name
    "\\mathnormal" "\\mathrm" "\\mathit" "\\mathbf" "\\mathsf" "\\mathtt" "\\mathcal" "\\mathscr"
    "\\mathbb" "\\mathfrak" "\\bm" "\\symup" "\\symit" "\\symbf" "\\symsf" "\\symtt" "\\symbfup"
    "\\symbfit" "\\symsfup" "\\symsfit" "\\symbfsf" "\\symbfsfup" "\\symbfsfit" "\\symcal"
    "\\symbfcal" "\\symscr" "\\symbfscr" "\\symbb" "\\symbbit" "\\symfrak" "\\symbffrak" "\\mathup"
    "\\mathbfup" "\\mathbfit" "\\mathsfup" "\\mathsfit" "\\mathbfsf" "\\mathbfsfup" "\\mathbfsfit"
    "\\mathbfcal" "\\mathbfscr" "\\mathbbit" "\\mathbffrak")
  (#has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @tex_font_name text_mode)
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

; some commands are alias from unicode-math but also work with pdflatex. Conceal only with latin letters
(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    (text
      word: (word) @font_letter)
    "}" @right_paren)
  (#has-ancestor? @tex_font_name displayed_equation inline_formula math_environment)
  (#not-has-ancestor? @tex_font_name text_mode)
  (#any-of? @tex_font_name
    "\\mathrm" "\\mathit" "\\mathbf" "\\mathsf" "\\mathtt" "\\mathcal" "\\mathscr" "\\mathbb"
    "\\mathfrak" "\\mathup" "\\mathbfup" "\\mathbfit" "\\mathsfup" "\\mathsfit" "\\mathbfsf"
    "\\mathbfsfup" "\\mathbfsfit" "\\mathbfcal" "\\mathbfscr" "\\mathbbit" "\\mathbffrak")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  ; Regex removed - Rust hash table will filter valid font letters
  (#set-font! @font_letter @tex_font_name))

; conceal letters and greek letters commands
(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    (_) @font_letter
    "}" @right_paren)
  (#any-of? @tex_font_name
    "\\bar" "\\widetilde" "\\hat" "\\dot" "\\ddot" "\\bm" "\\symup" "\\symit" "\\symbf" "\\symsf"
    "\\symtt" "\\symbfup" "\\symbfit" "\\symsfup" "\\symsfit" "\\symbfsf" "\\symbfsfup"
    "\\symbfsfit" "\\symcal" "\\symbfcal" "\\symscr" "\\symbfscr" "\\symbb" "\\symbbit" "\\symfrak"
    "\\symbffrak")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  ; Regex removed - Rust hash table will filter valid characters/greek letters
  (#set-font! @font_letter @tex_font_name))
