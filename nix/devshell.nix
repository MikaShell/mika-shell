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
  wayland-scanner,
  dbus,
  libwebp,
  d-spy,
  python3,
  gobject-introspection,
  glib,
  librsvg,
  dconf,
  linuxKernel,
  typescript,
  esbuild,
  nodejs_24,
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
      lldb
      dbus
      libwebp
      librsvg # 为 GTK 加载svg图标提供支持

      wayland-scanner

      # NPM Package
      esbuild
      nodejs_24
      typescript

      # DBus test scripts require dbus-python and pygobject3
      glib
      gobject-introspection
      (python3.withPackages (ps:
        with ps; [
          pydbus
          pygobject3
          dbus-python
        ]))

      # Dev Tools
      devhelp
      d-spy
      linuxKernel.packages.linux_zen.perf
    ];
    MIKASHELL_CONFIG_DIR = "./example";
    # dconf 使得 GTK 可以读取 dconf 配置, 例如主题
    GIO_EXTRA_MODULES = "${dconf.lib}/lib/gio/modules:${glib-networking.out}/lib/gio/modules";
    TERMINAL = "kitty";
    shellHook = ''
      export XDG_DATA_DIRS=${docs}:$XDG_DATA_DIRS
    '';
  }
