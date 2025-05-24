; physics conceal rules for LaTeX
; \bra{a} -> |a> \ket{a} -> <a|
; TODO: faster conceal rules for physics commands
(generic_command
  command: ((command_name) @cmd (#eq? @cmd "\\bra"))
  (#has-ancestor? @cmd math_environment inline_formula displayed_equation)
  (#set! priority 101)
  (#set! conceal "<"))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\bra")
  arg: (curly_group "{" @open1)
  (#has-ancestor? @open1 math_environment inline_formula displayed_equation)
  (#set! conceal ""))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\bra")
  arg: (curly_group "}" @close1)
  (#has-ancestor? @close1 math_environment inline_formula displayed_equation)
  (#set! conceal "|"))

(generic_command
  command: ((command_name) @cmd (#eq? @cmd "\\ket"))
  (#has-ancestor? @cmd math_environment inline_formula displayed_equation)
  (#set! priority 101)
  (#set! conceal "|"))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\ket")
  arg: (curly_group "{" @open1)
  (#has-ancestor? @open1 math_environment inline_formula displayed_equation)
  (#set! conceal ""))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\ket")
  arg: (curly_group "}" @close1)
  (#has-ancestor? @close1 math_environment inline_formula displayed_equation)
  (#set! conceal ">"))
