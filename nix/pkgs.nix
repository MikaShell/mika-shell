{
  nixpkgs,
  system,
  ...
}: let
  pkgs = import nixpkgs {inherit system;};
  mikami = pkgs.callPackage ./package.nix {};
in {
  default = mikami;
}
