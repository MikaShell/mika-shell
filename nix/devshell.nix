{
  lib,
  pkgs,
  mkShell,
  pkg-config,
  zig,
  zls,
  lldb,
  gtk4,
  webkitgtk_6_0,
  gtk4-layer-shell,
  zlib,
  glib-networking,
  openssl,
  devhelp,
  dbus,
  d-spy,
  python3,
  gobject-introspection,
  glib,
  ...
}: let
  # zig 不支持 -mfpmath=sse 选项
  custom-pkg-config = pkgs.writeScriptBin "pkg-config" ''
    #!/usr/bin/env bash
    exec ${pkgs.pkg-config}/bin/pkg-config "$@" | sed 's/-mfpmath=sse//g'
  '';
  docs = lib.makeSearchPathOutput "devdoc" "share" [
    gtk4
    webkitgtk_6_0
    glib
  ];
in
  mkShell {
    buildInputs = [
      custom-pkg-config
      pkg-config
      zig
      zls
      gtk4-layer-shell
      zlib
      openssl
      glib-networking
      gtk4
      webkitgtk_6_0
      devhelp
      lldb
      dbus
      d-spy
      # DBus test scripts require dbus-python and pygobject3
      glib
      gobject-introspection
      (python3.withPackages (ps:
        with ps; [
          pydbus
          pygobject3
        ]))
    ];
    GIO_EXTRA_MODULES = "${glib-networking.out}/lib/gio/modules";
    shellHook = ''
      export XDG_DATA_DIRS=${docs}:$XDG_DATA_DIRS
    '';
  }
