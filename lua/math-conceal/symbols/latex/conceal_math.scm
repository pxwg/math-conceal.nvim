; Due to the fact that some math environments work as generic, it is necessary
; to keep the concealment of math commands enabled for all modes
(generic_command
  command: (command_name) @cmd_escape
  (#set-escape! @cmd_escape "latex")
	(#set! priority 125))

(generic_command
  command: (command_name) @tex_math_command
  (#not-lua-match? @tex_math_command "^\\text")
  (#set-conceal! @tex_math_command "conceal"))

(generic_command
  command: (command_name) @conceal
  (#not-has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#lua-match? @conceal "^\\text")
  (#set-conceal! @conceal "conceal"))

(generic_command
  command: (command_name) @conceal
  (#has-ancestor? @conceal text_mode)
  (#lua-match? @conceal "^\\text")
  (#set-conceal! @conceal "conceal"))

; FRAC FUNCTIONS
; convert from
; \frac{expression_1}{expression_2}
; to
; `simple_1∕simple_2` and `(complex_expression_1complex_expression_2)`
; hide \frac
; hide `(`and `)` when expression is simple
; for simple expressions use `∕` DIVISION SLASH  U+2215
; for complex expressions use `` nerd fonts forwardslash_separator
; complex -> \frac{1+a}{2+b} -> (1+a2+b) -> (1+a)/(2+b)
(generic_command
  command: (command_name) @frac
  arg: (curly_group
    [
      "{" @left_1
      "}" @right_1
    ])
  .
  arg: (curly_group
    [
      "{" @left_2
      "}" @right_2
    ])
  (#any-of? @frac "\\frac" "\\dfrac" "\\tfrac" "\\cfrac")
  (#set! @frac conceal "")
  (#set! @left_1 conceal "(")
  (#set! @right_1 conceal "")
  (#set! @left_2 conceal "")
  (#set! @right_2 conceal ")"))

; simple -> \frac{a}{b} -> a∕b -> (a)/(b)
; `(generic_command)` dont work in choise `[]` with others to concatenate sub- or superscript
(generic_command
  command: (command_name) @frac
  arg: (curly_group
    "{" @left_1
    .
    [
      ((generic_command
        command: (command_name)
        .
        (curly_group) .)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      ((generic_command
        command: (command_name) .)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      (generic_command
        command: (command_name)
        .
        (curly_group) .)
      (generic_command
        command: (command_name) .)
      ((text_mode)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      (text
        .
        word: (word)
        .
        word: [
          (superscript)
          (subscript)
        ] .)
      (text
        .
        word: (word) .)
      (text_mode)
      (curly_group)
    ]
    .
    "}" @right_1)
  .
  arg: (curly_group
    "{" @left_2
    .
    [
      ((generic_command
        command: (command_name)
        .
        (curly_group) .)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      ((generic_command
        command: (command_name) .)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      (generic_command
        command: (command_name)
        .
        (curly_group) .)
      (generic_command
        command: (command_name) .)
      ((text_mode)
        .
        (text
          word: [
            (superscript)
            (subscript)
          ] .) .)
      (text
        .
        word: (word)
        .
        word: [
          (superscript)
          (subscript)
        ] .)
      (text
        .
        word: (word) .)
      (text_mode)
      (curly_group)
    ]
    .
    "}" @right_2)
  (#any-of? @frac "\\frac" "\\dfrac" "\\tfrac" "\\cfrac")
  (#set! @frac conceal "")
  (#set! @left_1 conceal "")
  (#set! @right_1 conceal "∕")
  (#set! @left_2 conceal "")
  (#set! @right_2 conceal ""))

(generic_command
  command: (command_name) @tex_math_command
  (#eq? @tex_math_command "\\sqrt")
  arg: (curly_group
    [
      "{" @left_paren_cmd
      "}" @right_paren_cmd
    ])
  (#set-conceal! @tex_math_command "conceal")
  (#set! @left_paren_cmd conceal "(")
  (#set! @right_paren_cmd conceal ")"))

; conceal when argument not in table(long word or other symbol)
(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @open_paren
    (_) @content
    "}" @close_paren)
  (#eq? @tex_math_command "\\overleftarrow")
  ; U+20D6 COMBINING LEFT ARROW ABOVE
  (#set! @open_paren conceal "⃖")
  (#set! @close_paren conceal "")
  (#set! @tex_math_command conceal ""))

(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @open_paren
    (_) @content
    "}" @close_paren)
  (#eq? @tex_math_command "\\overline")
  ; U+0305 COMBINING OVERLINE
  (#set! @open_paren conceal "̅")
  (#set! @close_paren conceal "")
  (#set! @tex_math_command conceal ""))

(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @open_paren
    (_) @content
    "}" @close_paren)
  (#eq? @tex_math_command "\\overrightarrow")
  ; U+20D7 COMBINING RIGHT ARROW ABOVE
  (#set! @open_paren conceal "⃗")
  (#set! @close_paren conceal "")
  (#set! @tex_math_command conceal ""))

(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @open_paren
    (_) @content
    "}" @close_paren)
  (#eq? @tex_math_command "\\widehat")
  ; U+0302 COMBINING CIRCUMFLEX ACCENT
  (#set! @open_paren conceal "̂")
  (#set! @close_paren conceal "")
  (#set! @tex_math_command conceal ""))

(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @open_paren
    (_) @content
    "}" @close_paren)
  (#eq? @tex_math_command "\\widetilde")
  ; U+0303 COMBINING TILDE
  (#set! @open_paren conceal "̃")
  (#set! @close_paren conceal "")
  (#set! @tex_math_command conceal ""))

((generic_command
  command: (command_name) @tex_math_command .)
  (#eq? @tex_math_command "\\tilde")
  (#set! @tex_math_command conceal "∼"))

(generic_command
  command: (command_name) @tex_math_command
  arg: (curly_group
    "{" @left_1
    (_) @content
    "}" @right_1)
  (#eq? @tex_math_command "\\abs")
  (#set! @left_1 conceal "￨")
  (#set! @right_1 conceal "￨")
  (#set! @tex_math_command conceal ""))

((math_environment
  [
    (begin
      (curly_group_text
        (text) @_env))
    (end
      (curly_group_text
        (text) @_env))
  ] @_line)
  (#any-of? @_env
    "math" "displaymath" "displaymath*" "equation" "equation*" "multline" "multline*" "eqnarray"
    "eqnarray*" "align" "align*" "gather" "gather*" "flalign" "flalign*")
  (#set! @_line conceal ""))

; non standart math_environment
(generic_environment
  [
    (begin
      (curly_group_text
        (text) @_env))
    (end
      (curly_group_text
        (text) @_env))
  ] @_line
  (#any-of? @_env
    "dgroup" "dgroup*" "dmath" "dmath*" "dseries" "dseries*" "empheq" "multsubequations"
    "subequations" "termlist" "termlist*")
  (#set! @_line conceal ""))

; TODO: Add it as a config key
((command_name) @cmd
  (#eq? @cmd "\\ali")
  arg: (curly_group
    "{" @left_paren
    (_)
    "}" @right_paren)
  (#set! conceal ""))
