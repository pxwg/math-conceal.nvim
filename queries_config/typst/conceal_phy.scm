; Typst physics symbol conceals - regex removed, Rust will filter
; Physics constants and symbols
(call
  item: (ident) @typ_phy_symbol
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set! priority 98)
  (#set-conceal! @typ_phy_symbol "conceal"))

; Physics units and quantities
((ident) @typ_phy_symbol
  ; (#has-ancestor? @typ_phy_symbol math formula)
  (#set! priority 98)
  (#set-conceal! @typ_phy_symbol "conceal"))

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
