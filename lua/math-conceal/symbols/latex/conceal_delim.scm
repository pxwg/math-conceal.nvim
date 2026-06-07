; Due to the fact that some math environments work as generic, it is necessary
; to keep the concealment of math commands enabled for all modes
(curly_group
  [
    "{"
    "}"
  ] @conceal
  (#not-has-grandparent? @conceal
    title_declaration author_declaration chapter part section subsection subsubsection paragraph
    subparagraph command generic_command subscript superscript)
  (#set! conceal ""))

; Useful for visual concatenate in conceal: \textbackslash{}command -> \command
; $a{}b$ -> $ab$ - two words
; LaTeX output produce same
(generic_command
  command: (command_name)
  (curly_group) @conceal
  (#match? @conceal "^\\{\\}$")
  (#set! @conceal conceal ""))

; Hints to simplify concealing
; \frac{{long_expression_1}}{{long_expression_2}}
;       ^               ^    ^                 ^
; conceal inner to
; {(long_expression)}
; \frac{{1+1}}{{2+2}} -> (1+1)/(2+2)
(generic_command
  command: (command_name) @frac
  (curly_group
    .
    (curly_group
      [
        "{" @left_1
        "}" @right_1
      ]) .)
  (#any-of? @frac "\\frac" "\\dfrac" "\\tfrac" "\\cfrac")
  (#set! @left_1 conceal "(")
  (#set! @right_1 conceal ")"))

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
  [
    "\\["
    "\\]"
  ] @conceal_dollar
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

("\\item*" @punctuation.special @conceal
  (#set! conceal "●"))

((text
  word: (delimiter) @conceal)
  (#eq? @conceal "&")
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
