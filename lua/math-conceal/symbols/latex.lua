local M = {}

M.conceal_math = [[
; math conceals
(generic_command
  command: ((command_name) @tex_math_command
  (#match? @tex_math_command "^\\\\(\\||amalg|angle|approx|ast|asymp|backslash|bigcap|bigcirc|bigcup|bigodot|bigoplus|bigotimes|bigsqcup|bigtriangledown|bigtriangleup|bigvee|bigwedge|bot|bowtie|bullet|cap|cdot|cdots|circ|cong|coprod|copyright|cup|dagger|dashv|ddagger|ddots|diamond|div|doteq|dots|downarrow|Downarrow|equiv|exists|flat|forall|frown|ge|geq|gets|gg|hookleftarrow|hookrightarrow|iff|Im|in|int|jmath|land|lceil|ldots|le|left|leftarrow|Leftarrow|leftharpoondown|leftharpoonup|leftrightarrow|Leftrightarrow|leq|lfloor|ll|lmoustache|lor|mapsto|mid|models|mp|nabla|natural|ne|nearrow|neg|neq|ni|notin|nwarrow|odot|oint|ominus|oplus|oslash|otimes|owns|P|parallel|partial|perp|pm|prec|preceq|prime|prod|propto|rceil|Re|quad|qquad|rfloor|right|rightarrow|Rightarrow|rightleftharpoons|rmoustache|S|searrow|setminus|sharp|sim|simeq|smile|sqcap|sqcup|sqsubset|sqsubseteq|sqsupset|sqsupseteq|star|subset|subseteq|succ|succeq|sum|supset|supseteq|surd|swarrow|times|to|top|triangle|triangleleft|triangleright|uparrow|Uparrow|updownarrow|Updownarrow|vdash|vdots|vee|wedge|wp|wr|langle|rangle|\\{|\\}|,|circ|dashint|nolimits|leadsto|Box|)$"))
  (#has-ancestor? @tex_math_command math_environment inline_formula displayed_equation generic_command)
  (#not-has-ancestor? @tex_math_command label_definition text_mode)
  (#set-conceal! @tex_math_command "conceal"))

(generic_command
  command: ((command_name) @tex_math_command
    (#match? @tex_math_command "^\\\\(aleph|clubsuit|diamondsuit|heartsuit|spadesuit|ell|emptyset|varnothing|hbar|imath|infty)$"))
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
  (#match? @font_letter "^[a-zA-Z]$")
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
  (#match? @font_letter "^([a-zA-Z]|\\\\(alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|varepsilon|vartheta|varpi|varrho|varsigma|varphi|digamma|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega|Varepsilon|Vartheta|Varpi|Varrho|Varsigma|Varphi))$")
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
(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_) @sub_letter
    "}" @close_paren) @sub_object
  (#match? @sub_object "^\\{[aehijklmnoprstuvx1234567890]\\}$")
  (#set! priority 101)
  (#set! @sub_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sub! @sub_letter))

(subscript
  "_" @sub_symbol
  subscript: (curly_group
    "{" @open_paren
    (_)
    "}" @close_paren) @sub_object
  (#match? @sub_object "^\\{\\\\\\S+\\}")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(subscript
  "_" @sub_symbol
  subscript: (_) @sub_object
  (#match? @sub_object "^[aehijklmnoprstuvx1234567890]$")
  (#set! @sub_symbol conceal "")
  (#set-sub! @sub_object))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    (_) @sup_letter
    "}" @close_paren) @sup_object
  (#match? @sup_object "^\\{[a-z0-9]\\}$")
  (#set! @sup_symbol conceal "")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal "")
  (#set-sup! @sup_letter))

(superscript
  "^" @sup_symbol
  superscript: (curly_group
    "{" @open_paren
    "}" @close_paren) @sup_object
  (#match? @sup_object "^\\{\\\\\\S+\\}$")
  (#set! @open_paren conceal "")
  (#set! @close_paren conceal ""))

(superscript
  "^" @sup_symbol
  superscript: (_) @sup_object
  (#match? @sup_object "^[a-z0-9]$")
  (#set! @sup_symbol conceal "")
  (#set-sup! @sup_object))

]]

M.conceal_greek = [[
; greek conceal
(generic_command
  command: ((command_name) @tex_greek
    (#match? @tex_greek "^\\\\(varalpha|varbeta|vargamma|vardelta|varepsilon|varzeta|vareta|vartheta|variota|varkappa|varlambda|varmu|varnu|varxi|varpi|varrho|varsigma|vartau|varupsilon|varphi|varchi|varpsi|varomega|alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega)$"))
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))

(generic_command
  command: ((command_name) @tex_greek
    (#match? @tex_greek "^\\\\(Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Chi|Psi|Omega)$"))
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))

]]

return M
