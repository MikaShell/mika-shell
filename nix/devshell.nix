{
  pkgs,
  mkShell,
  pkg-config,
  zig,
  zls,
  gtk4,
  webkitgtk_6_0,
  gtk4-layer-shell,
  librsvg,
  ...
}: let
  # zig 不支持 -mfpmath=sse 选项
  custom-pkg-config = pkgs.writeScriptBin "pkg-config" ''
    #!/usr/bin/env bash
    exec ${pkgs.pkg-config}/bin/pkg-config "$@" | sed 's/-mfpmath=sse//g'
  '';
in
  mkShell {
    buildInputs = [
      custom-pkg-config
      pkg-config
      zig
      zls
      gtk4
      webkitgtk_6_0
      gtk4-layer-shell
      librsvg
    ];
  }
