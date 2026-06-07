; Due to the fact that some math environments work as generic, it is necessary
; to keep the concealment of math commands enabled for all modes
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
    "\\acute" "\\bar" "\\breve" "\\check" "\\ddddot" "\\dddot" "\\ddot" "\\dot" "\\grave" "\\hat"
    "\\tilde" "\\vec" "\\mathnormal" "\\mathrm" "\\mathit" "\\mathbf" "\\mathsf" "\\mathtt"
    "\\mathcal" "\\mathscr" "\\mathbb" "\\mathfrak" "\\bm" "\\symup" "\\symit" "\\symbf" "\\symsf"
    "\\symtt" "\\symbfup" "\\symbfit" "\\symsfup" "\\symsfit" "\\symbfsf" "\\symbfsfup"
    "\\symbfsfit" "\\symcal" "\\symbfcal" "\\symscr" "\\symbfscr" "\\symbb" "\\symbbit" "\\symfrak"
    "\\symbffrak" "\\mathup" "\\mathbfup" "\\mathbfit" "\\mathsfup" "\\mathsfit" "\\mathbfsf"
    "\\mathbfsfup" "\\mathbfsfit" "\\mathbfcal" "\\mathbfscr" "\\mathbbit" "\\mathbffrak")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal ""))

; some commands are alias from unicode-math but also work with pdflatex. Conceal only with latin letters or digits
; conceal letters, digits and greek letters commands
(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    [
      (_) @font_letter
      (text
        word: (word) @font_letter)
    ]
    "}" @right_paren)
  (#any-of? @tex_font_name
    "\\acute" "\\bar" "\\breve" "\\check" "\\ddddot" "\\dddot" "\\ddot" "\\dot" "\\grave" "\\hat"
    "\\tilde" "\\vec" "\\mathnormal" "\\mathrm" "\\mathit" "\\mathbf" "\\mathsf" "\\mathtt"
    "\\mathcal" "\\mathscr" "\\mathbb" "\\mathfrak" "\\bm" "\\symup" "\\symit" "\\symbf" "\\symsf"
    "\\symtt" "\\symbfup" "\\symbfit" "\\symsfup" "\\symsfit" "\\symbfsf" "\\symbfsfup"
    "\\symbfsfit" "\\symcal" "\\symbfcal" "\\symscr" "\\symbfscr" "\\symbb" "\\symbbit" "\\symfrak"
    "\\symbffrak" "\\mathup" "\\mathbfup" "\\mathbfit" "\\mathsfup" "\\mathsfit" "\\mathbfsf"
    "\\mathbfsfup" "\\mathbfsfit" "\\mathbfcal" "\\mathbfscr" "\\mathbbit" "\\mathbffrak")
  (#set! @left_paren conceal "")
  (#set! @right_paren conceal "")
  (#set! @tex_font_name conceal "")
  (#set-font! @font_letter @tex_font_name))

; digits or number only in math mode
(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{"
    [
      (_) @font_digit
      (text
        word: (word) @font_digit)
    ]
    "}")
  (#lua-match? @font_digit "^%d+$")
  (#set-font! @font_digit @tex_font_name)
  (#set! priority 101))
