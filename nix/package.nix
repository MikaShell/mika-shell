{
  lib,
  pkgs,
  pkg-config,
  zig,
  gtk4,
  webkitgtk_6_0,
  gtk4-layer-shell,
  zlib,
  glib-networking,
  openssl,
  dbus,
  callPackage,
  libwebp,
  glib,
  librsvg,
  esbuild,
  stdenv,
  wrapGAppsHook4,
  zig_0_14,
  wayland-scanner,
  systemd,
  libinput,
  debug ? false,
  ...
}: let
  # zig 不支持 -mfpmath=sse 选项
  custom-pkg-config = pkgs.writeScriptBin "pkg-config" ''
    #!/usr/bin/env bash
    exec ${pkgs.pkg-config}/bin/pkg-config "$@" | sed 's/-mfpmath=sse//g'
  '';
  optimize =
    if debug
    then "Debug"
    else "ReleaseFast";
  zig_hook = zig_0_14.hook.overrideAttrs {
    zig_default_flags = "-Dcpu=baseline -Doptimize=${optimize} --color off";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    name = "mika-shell";
    pname = "mika-shell";
    version = "0.0.0";
    src = ../.;
    postPatch = ''
      ln -s ${callPackage ../build.zig.zon.nix {name = "mika-shell-cache-${finalAttrs.version}";}} $ZIG_GLOBAL_CACHE_DIR/p
    '';
    nativeBuildInputs = [
      custom-pkg-config
      pkg-config
      esbuild
      zig
      zig_hook
      wrapGAppsHook4
    ];
    buildInputs = [
      gtk4
      glib-networking
      webkitgtk_6_0
      gtk4-layer-shell
      zlib
      openssl
      libwebp
      librsvg
      dbus
      glib
      wayland-scanner
      systemd # 提供 libudev
      libinput
    ];
    meta = {
      description = "Build your own desktop shell using HTML + CSS + JS";
      homepage = "https://github.com/HumXC/mika-shell";
      mainProgram = "mika-shell";
      platforms = lib.platforms.unix;
    };
  })
