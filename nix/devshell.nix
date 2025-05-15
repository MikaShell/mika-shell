{
  nixpkgs,
  system,
  ...
}: let
  pkgs = import nixpkgs {inherit system;};
  wails3 = pkgs.callPackage ./wails3.nix {};
in {
  default = pkgs.mkShell {
    buildInputs = with pkgs; [
      go
      nodejs
      gtk3
      webkitgtk_4_1
      gtk-layer-shell
      libwebp
      wails3
      typescript
      librsvg
      pkg-config
    ];
    CGO_CFLAGS = "-Wno-error=cpp";
    shellHook = ''
      if ! command -v wails3 &> /dev/null; then
        go install github.com/wailsapp/wails/v3/cmd/wails3@latest
      fi
    '';
  };
}
