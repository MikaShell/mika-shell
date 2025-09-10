{
  lib,
  pkgs,
  mkShell,
  pkg-config,
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
  libpng,
  systemd,
  gst_all_1,
  libinput,
  librsvg,
  dconf,
  linuxKernel,
  typescript,
  esbuild,
  nodejs_24,
  zon2nix,
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
  zig = pkgs.zig_0_15;
  zls = pkgs.zls_0_15;
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
      systemd # 提供 libudev
      libinput
      libpng

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
      zon2nix
    ];
    MIKASHELL_CONFIG_DIR = "./example";
    MIKASHELL_PORT = "6789";
    # dconf 使得 GTK 可以读取 dconf 配置, 例如主题
    GIO_EXTRA_MODULES = "${dconf.lib}/lib/gio/modules:${glib-networking.out}/lib/gio/modules";
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" [
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav
      gst_all_1.gstreamer
    ];
    TERMINAL = "kitty";
    shellHook = ''
      export XDG_DATA_DIRS=${docs}:$XDG_DATA_DIRS
    '';
  }
