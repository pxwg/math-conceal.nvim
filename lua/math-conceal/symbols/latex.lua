local M = {}

M.conceal_math = [[
; math conceals - regex removed, Rust hash table will filter
(generic_command
  command: (command_name) @tex_math_command
  (#has-ancestor? @tex_math_command math_environment inline_formula displayed_equation generic_command)
  (#not-has-ancestor? @tex_math_command label_definition text_mode)
  (#set-conceal! @tex_math_command "conceal"))

(generic_command
  command: (command_name) @frac
  (#any-of? @frac "\\frac" "\\dfrac" "\\tfrac" "\\cfrac")
  arg: (curly_group
    "{" @left_1
    (_)
    "}" @right_1)
  arg: (curly_group
    "{" @left_2
    (_)
    "}" @right_2)
  (#has-ancestor? @frac math_environment inline_formula displayed_equation generic_command)
  (#set! @frac conceal "")
  (#set! @left_1 conceal "(")
  (#set! @right_1 conceal "/")
  (#set! @left_2 conceal "")
  (#set! @right_2 conceal ")"))

(generic_command
        command: (command_name) @tex_math_command
        (#eq? @tex_math_command "\\sqrt")
        arg: (curly_group
          "{" @left_paren_cmd
          (text
            word: (word))
          "}" @right_paren_cmd)
        (#has-ancestor? @tex_math_command math_environment inline_formula displayed_equation)
        (#set-conceal! @tex_math_command "conceal")
        (#set! @left_paren_cmd conceal "(")
        (#set! @right_paren_cmd conceal ")"))


((math_environment
  (begin
    (curly_group_text
      (text) @_env))@_line)
  (#any-of? @_env "equation" "equation*")
  (#set! @_line conceal ""))

((math_environment
  (end
    (curly_group_text
      (text) @_env))@_line)
  (#any-of? @_env "equation" "equation*")
  (#set! @_line conceal ""))








;;; TODO: Add it as a config key
((command_name) @cmd
(#eq? @cmd "\\ali")
arg: (curly_group
       "{" @left_paren
       (_)
       "}" @right_paren)
(#set! conceal ""))

]]

M.conceal_font = [[
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

]]

M.conceal_phy = [[
; physics conceal rules for LaTeX
; \bra{a} -> |a> \ket{a} -> <a|
; TODO: faster conceal rules for physics commands
(generic_command
  command: (command_name) @cmd
  (#eq? @cmd "\\bra")
  arg: (curly_group
    "{" @left_brace
    (text
      word: (word))
    "}" @right_brace)
  (#has-ancestor? @left_brace math_environment inline_formula displayed_equation)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "|"))

(generic_command
  command: (command_name) @cmd
  (#eq? @cmd "\\ket")
  arg: (curly_group
    "{" @left_brace
    (text
      word: (word))
    "}" @right_brace)
  (#has-ancestor? @left_brace math_environment inline_formula displayed_equation)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "|")
  (#set! @right_brace conceal "⟩"))

]]

M.conceal_delim = [[
(curly_group
  "{" @conceal
  (#not-has-grandparent? @conceal
    title_declaration author_declaration chapter part section subsection subsubsection paragraph
    subparagraph command generic_command subscript superscript)
  (#set! conceal ""))

(curly_group
  "}" @conceal
  (#not-has-grandparent? @conceal
    title_declaration author_declaration chapter part section subsection subsubsection paragraph
    subparagraph command generic_command subscript superscript)
  (#set! conceal ""))

(math_delimiter
  left_command: _ @conceal
  (#set! conceal ""))

(math_delimiter
  right_command: _ @conceal
  (#set! conceal ""))

(inline_formula
  "$" @conceal_dollar
  (#set! conceal ""))

(inline_formula
  "\\(" @conceal_dollar
  (_)
  "\\)" @conceal_dollar
  (#set! @conceal_dollar conceal ""))

(displayed_equation
  "\\[" @conceal_dollar
  "\\]" @conceal_dollar
  (#set! @conceal_dollar conceal ""))

(displayed_equation
  "$$" @conceal_dollar
  (#set! conceal ""))
  ; (#set! conceal_lines ""))

(text_mode
  command: _ @conceal
  (#set! conceal ""))

("\\item" @punctuation.special @conceal
  (#set! conceal "○"))

((text
  word: (delimiter) @conceal)
  (#eq? @conceal "&")
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#set! conceal ""))

(math_delimiter
  left_delimiter: (command_name) @punctuation.delimiter
  (#eq? @punctuation.delimiter "\\{")
  (#set! conceal "{")
  (_))

(math_delimiter
  (_)
  right_delimiter: (command_name) @punctuation.delimiter
  (#eq? @punctuation.delimiter "\\}")
  (#set! conceal "}"))

]]

M.conceal_script = [[
; Subscript with curly group - regex removed, Rust will filter via hash lookup
(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_) @sub_letter
    "}" @close_paren) @sub_object
  (#set! priority 101)
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_letter))

; Subscript direct - regex removed, Rust will filter via hash lookup
(subscript
  "_" @sub_symbol
  subscript: (_) @sub_object
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object))

; Superscript with curly group - regex removed, Rust will filter via hash lookup
(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (_) @sup_letter
    "}" @close_paren) @sup_object
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_letter))

; Superscript direct - regex removed, Rust will filter via hash lookup
(superscript
  "^" @sup_symbol
  superscript: (_) @sup_object
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object))

]]

M.conceal_greek = [[
; greek conceal - regex removed, Rust hash table will filter
(generic_command
  command: (command_name) @tex_greek
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))

]]

return M
