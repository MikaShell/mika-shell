{
  nixpkgs,
  system,
  ...
}: let
  pkgs = import nixpkgs {inherit system;};
  mikami = pkgs.callPackage ./package.nix {};
  wails3 = pkgs.callPackage ./wails3.nix {};
in {
  default = mikami;
  wails3 = wails3;
}
