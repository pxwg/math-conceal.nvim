; greek conceal - regex removed, Rust hash table will filter
(generic_command
  command: (command_name) @tex_greek
  ; (#has-parent? @tex_greek math_environment)
  (#set-conceal! @tex_greek "conceal"))
