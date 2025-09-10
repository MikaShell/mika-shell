{
  lib,
  pkgs,
  pkg-config,
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
  wayland-scanner,
  systemd,
  libinput,
  libpng,
  debug ? false,
  ...
}: let
  # zig 不支持 -mfpmath=sse 选项
  custom-pkg-config = pkgs.writeScriptBin "pkg-config" ''
    #!/usr/bin/env bash
    exec ${pkgs.pkg-config}/bin/pkg-config "$@" | sed 's/-mfpmath=sse//g'
  '';
  release =
    if debug
    then "off"
    else "fast";
  zig = pkgs.zig_0_15;
  zig_hook = zig.hook.overrideAttrs {
    zig_default_flags = "--release=${release} --color off";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    name = "mika-shell";
    pname = "mika-shell";
    version = "0.0.0";
    src = ../.;
    deps = callPackage ../build.zig.zon.nix {};
    zigBuildFlags = ["--system" "${finalAttrs.deps}"];
    nativeBuildInputs = [
      custom-pkg-config
      pkg-config
      esbuild
      zig
      zig_hook
      wrapGAppsHook4
    ];
    dontStrip = debug;
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
      libpng
    ];
    meta = {
      description = "Build your own desktop shell using HTML + CSS + JS";
      homepage = "https://github.com/HumXC/mika-shell";
      mainProgram = "mika-shell";
      platforms = lib.platforms.unix;
    };
  })
