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
