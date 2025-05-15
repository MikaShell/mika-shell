{
  nixpkgs,
  system,
  ...
}: let
  pkgs = import nixpkgs {inherit system;};
  mikami = pkgs.callPackage ./package.nix {};
  mikami-debug = pkgs.callPackage ./package.nix {debug = true;};
  wails3 = pkgs.callPackage ./wails3.nix {};
in {
  default = mikami;
  dev = mikami-debug;
  wails3 = wails3;
}
