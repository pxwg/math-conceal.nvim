(generic_command
  command: (command_name) @conceal
  (#any-of? @conceal "\\emph" "\\mathit" "\\textit" "\\mathbf" "\\textbf")
  (#set! conceal ""))

((generic_command
  command: (command_name)
  arg: (curly_group)) @conceal
  (#any-of? @conceal
    "\\mathbb{A}" "\\mathbb{B}" "\\mathbb{C}" "\\mathbb{D}" "\\mathbb{E}" "\\mathbb{F}"
    "\\mathbb{G}" "\\mathbb{H}" "\\mathbb{I}" "\\mathbb{J}" "\\mathbb{K}" "\\mathbb{L}"
    "\\mathbb{M}" "\\mathbb{N}" "\\mathbb{O}" "\\mathbb{P}" "\\mathbb{Q}" "\\mathbb{R}"
    "\\mathbb{S}" "\\mathbb{T}" "\\mathbb{U}" "\\mathbb{V}" "\\mathbb{W}" "\\mathbb{X}"
    "\\mathbb{Y}" "\\mathbb{Z}" "\\mathsf{a}" "\\mathsf{b}" "\\mathsf{c}" "\\mathsf{d}"
    "\\mathsf{e}" "\\mathsf{f}" "\\mathsf{g}" "\\mathsf{h}" "\\mathsf{i}" "\\mathsf{j}"
    "\\mathsf{k}" "\\mathsf{l}" "\\mathsf{m}" "\\mathsf{n}" "\\mathsf{o}" "\\mathsf{p}"
    "\\mathsf{q}" "\\mathsf{r}" "\\mathsf{s}" "\\mathsf{t}" "\\mathsf{u}" "\\mathsf{v}"
    "\\mathsf{w}" "\\mathsf{x}" "\\mathsf{y}" "\\mathsf{z}" "\\mathsf{A}" "\\mathsf{B}"
    "\\mathsf{C}" "\\mathsf{D}" "\\mathsf{E}" "\\mathsf{F}" "\\mathsf{G}" "\\mathsf{H}"
    "\\mathsf{I}" "\\mathsf{J}" "\\mathsf{K}" "\\mathsf{L}" "\\mathsf{M}" "\\mathsf{N}"
    "\\mathsf{O}" "\\mathsf{P}" "\\mathsf{Q}" "\\mathsf{R}" "\\mathsf{S}" "\\mathsf{T}"
    "\\mathsf{U}" "\\mathsf{V}" "\\mathsf{W}" "\\mathsf{X}" "\\mathsf{Y}" "\\mathsf{Z}"
    "\\mathfrak{a}" "\\mathfrak{b}" "\\mathfrak{c}" "\\mathfrak{d}" "\\mathfrak{e}" "\\mathfrak{f}"
    "\\mathfrak{g}" "\\mathfrak{h}" "\\mathfrak{i}" "\\mathfrak{j}" "\\mathfrak{k}" "\\mathfrak{l}"
    "\\mathfrak{m}" "\\mathfrak{n}" "\\mathfrak{o}" "\\mathfrak{p}" "\\mathfrak{q}" "\\mathfrak{r}"
    "\\mathfrak{s}" "\\mathfrak{t}" "\\mathfrak{u}" "\\mathfrak{v}" "\\mathfrak{w}" "\\mathfrak{x}"
    "\\mathfrak{y}" "\\mathfrak{z}" "\\mathfrak{A}" "\\mathfrak{B}" "\\mathfrak{C}" "\\mathfrak{D}"
    "\\mathfrak{E}" "\\mathfrak{F}" "\\mathfrak{G}" "\\mathfrak{H}" "\\mathfrak{I}" "\\mathfrak{J}"
    "\\mathfrak{K}" "\\mathfrak{L}" "\\mathfrak{M}" "\\mathfrak{N}" "\\mathfrak{O}" "\\mathfrak{P}"
    "\\mathfrak{Q}" "\\mathfrak{R}" "\\mathfrak{S}" "\\mathfrak{T}" "\\mathfrak{U}" "\\mathfrak{V}"
    "\\mathfrak{W}" "\\mathfrak{X}" "\\mathfrak{Y}" "\\mathfrak{Z}" "\\mathscr{A}" "\\mathscr{B}"
    "\\mathscr{C}" "\\mathscr{D}" "\\mathscr{E}" "\\mathscr{F}" "\\mathscr{G}" "\\mathscr{H}"
    "\\mathscr{I}" "\\mathscr{J}" "\\mathscr{K}" "\\mathscr{L}" "\\mathscr{M}" "\\mathscr{N}"
    "\\mathscr{O}" "\\mathscr{P}" "\\mathscr{Q}" "\\mathscr{R}" "\\mathscr{S}" "\\mathscr{T}"
    "\\mathscr{U}" "\\mathscr{V}" "\\mathscr{W}" "\\mathscr{X}" "\\mathscr{Y}" "\\mathscr{Z}"
    "\\mathcal{A}" "\\mathcal{B}" "\\mathcal{C}" "\\mathcal{D}" "\\mathcal{E}" "\\mathcal{F}"
    "\\mathcal{G}" "\\mathcal{H}" "\\mathcal{I}" "\\mathcal{J}" "\\mathcal{K}" "\\mathcal{L}"
    "\\mathcal{M}" "\\mathcal{N}" "\\mathcal{O}" "\\mathcal{P}" "\\mathcal{Q}" "\\mathcal{R}"
    "\\mathcal{S}" "\\mathcal{T}" "\\mathcal{U}" "\\mathcal{V}" "\\mathcal{W}" "\\mathcal{X}"
    "\\mathcal{Y}" "\\mathcal{Z}")
  (#lua_func! @conceal "conceal"))
