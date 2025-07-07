{
  nixpkgs,
  system,
  ...
}: let
  pkgs = import nixpkgs {inherit system;};
  mika-shell = pkgs.callPackage ./package.nix {};
  maka-shell-debug = pkgs.callPackage ./package.nix {debug = true;};
in {
  default = mika-shell;
  debug = maka-shell-debug;
}
