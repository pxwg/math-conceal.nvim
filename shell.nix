{
  pkgs ? import <nixpkgs> { },
}:

with pkgs;
mkShell {
  name = "math-conceal.nvim";
  buildInputs = [
    cargo

    (luajit.withPackages (
      p: with p; [
        busted
        ldoc
        luarocks-build-rust-mlua
      ]
    ))
  ];
}
