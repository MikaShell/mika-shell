{nixpkgs, ...}: {
  default = final: _prev: let
    packages = import ./pkgs.nix {
      inherit nixpkgs;
      system = final.system;
    };
  in {
    mikami.default = packages.default;
  };
}
