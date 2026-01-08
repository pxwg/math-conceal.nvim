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
