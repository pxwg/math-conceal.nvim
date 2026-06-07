; Due to the fact that some math environments work as generic, it is necessary
; to keep the concealment of math commands enabled for all modes
(generic_command
  command: (command_name) @tex_greek
  (#not-lua-match? @tex_greek "^\\text")
  (#set-greek! @tex_greek "greek"))

(generic_command
  command: (command_name) @conceal
  (#not-has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#lua-match? @conceal "^\\text")
  (#set-greek! @conceal "greek"))

(generic_command
  command: (command_name) @conceal
  (#has-ancestor? @conceal text_mode)
  (#lua-match? @conceal "^\\text")
  (#set-greek! @conceal "greek"))

(generic_command
  command: (command_name) @tex_font_name
  arg: (curly_group
    "{" @left_paren
    [
      (_) @tex_greek
      (text
        word: (word) @tex_greek)
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
  (#set-greek_font! @tex_greek @tex_font_name))
