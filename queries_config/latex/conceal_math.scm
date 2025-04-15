; math conceals
(generic_command
  command: ((command_name) @conceal
  (#any-of? @conceal
   "\\|" "\\amalg" "\\angle" "\\approx" 
   "\\ast" "\\asymp" "\\backslash" "\\bigcap" 
   "\\bigcirc" "\\bigcup" "\\bigodot" "\\bigoplus" 
   "\\bigotimes" "\\bigsqcup" "\\bigtriangledown" "\\bigtriangleup" 
   "\\bigvee" "\\bigwedge" "\\bot" "\\bowtie" "\\bullet"
   "\\cap" "\\cdot" "\\cdots" "\\circ" "\\cong" "\\coprod" 
   "\\copyright" "\\cup" "\\dagger" "\\dashv" "\\ddagger" 
   "\\ddots" "\\diamond" "\\div" "\\doteq" "\\dots" 
   "\\downarrow" "\\Downarrow" "\\equiv" "\\exists" "\\flat" 
   "\\forall" "\\frown" "\\ge" "\\geq" "\\gets" "\\gg" "\\hookleftarrow" 
   "\\hookrightarrow" "\\iff" "\\Im" "\\in" "\\int" "\\jmath" 
   "\\land" "\\lceil" "\\ldots" "\\le" "\\left" "\\leftarrow" "\\Leftarrow" 
   "\\leftharpoondown" "\\leftharpoonup" "\\leftrightarrow" "\\Leftrightarrow" 
   "\\leq" "\\leq" "\\lfloor" "\\ll" "\\lmoustache" "\\lor" "\\mapsto" 
   "\\mid" "\\models" "\\mp" "\\nabla" "\\natural" "\\ne" "\\nearrow" 
   "\\neg" "\\neq" "\\ni" "\\notin" "\\nwarrow" "\\odot" "\\oint" 
   "\\ominus" "\\oplus" "\\oslash" "\\otimes" "\\owns" "\\P" 
   "\\parallel" "\\partial" "\\perp" "\\pm" "\\prec" "\\preceq" 
   "\\prime" "\\prod" "\\propto" "\\rceil" "\\Re" "\\quad" "\\qquad" 
   "\\rfloor" "\\right" "\\rightarrow" "\\Rightarrow" "\\rightleftharpoons" 
   "\\rmoustache" "\\S" "\\searrow" "\\setminus" "\\sharp" "\\sim" 
   "\\simeq" "\\smile" "\\sqcap" "\\sqcup" "\\sqsubset" "\\sqsubseteq" 
   "\\sqsupset" "\\sqsupseteq" "\\star" "\\subset" "\\subseteq" 
   "\\succ" "\\succeq" "\\sum" "\\supset" "\\supseteq" 
   "\\surd" "\\swarrow" "\\times" "\\to" "\\top" 
   "\\triangle" "\\triangleleft" "\\triangleright" "\\uparrow" 
   "\\Uparrow" "\\updownarrow" "\\Updownarrow" "\\vdash" "\\vdots" 
   "\\vee" "\\wedge" "\\wp" "\\wr" "\\langle" "\\rangle" "\\{" "\\}" "\\," "\\circ"))
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#lua_func! @conceal "conceal"))

(generic_command
  command: ((command_name) @conceal
  (#any-of? @conceal 
   "\\aleph" "\\clubsuit" "\\diamondsuit" "\\heartsuit"
   "\\spadesuit" "\\ell" "\\emptyset" "\\varnothing"
   "\\hbar" "\\imath" "\\infty"))
  (#has-ancestor? @conceal math_environment inline_formula displayed_equation)
  (#not-has-ancestor? @conceal label_definition text_mode)
  (#lua_func! @conceal "conceal"))

; Conceal \frac command and brackets to show as numerator/denominator
(generic_command
  command: ((command_name) @cmd (#eq? @cmd "\\frac"))
  (#has-ancestor? @cmd math_environment inline_formula displayed_equation)
  (#set! conceal ""))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\frac")
  arg: (curly_group "{" @open1)
  (#has-ancestor? @open1 math_environment inline_formula displayed_equation)
  (#set! conceal ""))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\frac")
  arg: (curly_group "}" @close1)
  arg: (curly_group)
  (#has-ancestor? @close1 math_environment inline_formula displayed_equation)
  (#set! conceal "/"))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\frac")
  arg: (curly_group)
  arg: (curly_group "{" @open2)
  (#has-ancestor? @open2 math_environment inline_formula displayed_equation)
  (#set! conceal ""))

(generic_command
  command: (command_name) @_cmd (#eq? @_cmd "\\frac")
  arg: (curly_group)
  arg: (curly_group "}" @close2)
  (#has-ancestor? @close2 math_environment inline_formula displayed_equation)
  (#set! conceal ""))
