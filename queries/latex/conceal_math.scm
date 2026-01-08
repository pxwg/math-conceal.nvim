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
