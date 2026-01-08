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
