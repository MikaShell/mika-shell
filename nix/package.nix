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
  polkit,
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
  stdenv.mkDerivation (finalAttrs: rec {
    name = "mika-shell";
    pname = "mika-shell";
    version = "0.0.0";
    src = ../.;
    deps = callPackage ../build.zig.zon.nix {};
    zigBuildFlags = [
      "--system"
      "${finalAttrs.deps}"
      "-Dcpu=baseline"
      "-Dversion-string=${version}"
      "-Dcommit-hash=fffffff"
    ];
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
    # https://github.com/imvaskel/soteria/blob/1cb43e1049e23f27ff4f2beb6c1f517da0635f53/package.nix#L47
    # Takes advantage of nixpkgs manually editing PACKAGE_PREFIX by grabbing it from
    # the binary itself.
    # https://github.com/NixOS/nixpkgs/blob/9b5328b7f761a7bbdc0e332ac4cf076a3eedb89b/pkgs/development/libraries/polkit/default.nix#L142
    # https://github.com/polkit-org/polkit/blob/d89c3604e2a86f4904566896c89e1e6b037a6f50/src/polkitagent/polkitagentsession.c#L599
    preBuild = ''
      export POLKIT_AGENT_HELPER_PATH="$(strings ${polkit.out}/lib/libpolkit-agent-1.so | grep "polkit-agent-helper-1")"
    '';
    meta = {
      description = "Build your own desktop shell using HTML + CSS + JS";
      homepage = "https://github.com/MikaShell/mika-shell";
      mainProgram = "mika-shell";
      platforms = lib.platforms.unix;
    };
  })
