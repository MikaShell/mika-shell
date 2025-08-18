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
  release =
    if debug
    then "off"
    else "fast";
  zig_hook = zig_0_14.hook.overrideAttrs {
    zig_default_flags = "--release=${release} --color off";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    name = "mika-shell";
    pname = "mika-shell";
    version = "0.0.0";
    src = ../.;
    deps = callPackage ../build.zig.zon.nix {name = "mika-shell-cache-${finalAttrs.version}";};
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
    ];
    meta = {
      description = "Build your own desktop shell using HTML + CSS + JS";
      homepage = "https://github.com/HumXC/mika-shell";
      mainProgram = "mika-shell";
      platforms = lib.platforms.unix;
    };
  })
