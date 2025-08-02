; Typst physics symbol conceals
; Physics constants and symbols
(call
  item: (ident) @typ_phy_symbol
  (#match? @typ_phy_symbol "^(hbar|planck|boltzmann|avogadro|gas|electron|proton|neutron|muon|tau|charge|mass|energy|momentum|angular|spin|magnetic|electric|permittivity|permeability|speed|light|gravity|acceleration|force|pressure|temperature|entropy|enthalpy|helmholtz|gibbs)$")
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Physics units and quantities
((ident) @typ_phy_symbol
  (#match? @typ_phy_symbol "^(hbar|planck|boltzmann|avogadro|electron|proton|neutron|speed|light|gravity|charge|mass|energy|momentum|angular|spin|magnetic|electric|force|pressure|temperature|entropy|enthalpy|helmholtz|gibbs)$")
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Vector and tensor notation
((ident) @func
  (#any-of? @func "vec" "hat" "tilde" "bar" "dot" "ddot" "dddot")
  ; (#has-ancestor? @func math formula)
  (#set! conceal ""))

; Derivatives and differentials
((ident) @func
  (#any-of? @func "diff" "pdiff" "grad" "div" "curl" "laplacian")
  ; (#has-ancestor? @func math formula)
  (#set-conceal! @func "conceal"))

; Physics operators
((ident) @func
  (#any-of? @func "expval" "mel" "bra" "ket" "braket" "ketbra" "op")
  ; (#has-ancestor? @func math formula)
  (#set-conceal! @func "conceal"))

((call
        item: (ident) @cmd
        "(" @left_brace
        (#eq? @cmd "bra")
        (_)
        ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "|"))

((call
        item: (ident) @cmd
        "(" @left_brace
        (#eq? @cmd "ket")
        (_)
        ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @right_brace conceal "⟩")
  (#set! @left_brace conceal "|"))

;; For braket(a,b) -> ⟨a|b⟩
((call
      item: (ident) @cmd
      "(" @left_brace
      (#eq? @cmd "braket")
      (formula) @left_content
      "," @comma
      (formula) @right_content
      ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @comma conceal "|")
  (#set! @right_brace conceal "⟩"))

;; TODO: For braket(ab) -> ⟨ab|ab⟩
((call
      item: (ident) @cmd
      "(" @left_brace
      (#eq? @cmd "braket")
      (formula
        (letter) @first_letter
        (letter) @second_letter) @content
      ")" @right_brace)
  (#set! @cmd conceal "")
  (#set! @left_brace conceal "⟨")
  (#set! @right_brace conceal "⟩"))
