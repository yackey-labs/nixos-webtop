# pixelflux: Selkies' X11/Wayland capture + x264/jpeg encoder. Upstream publishes
# only manylinux wheels (no sdist that builds cleanly), so we consume the wheel
# and let autoPatchelf wire it to Nix's libraries.
#
# 2.1.0 is NOT on PyPI -- PyPI still shows 2.0.0 -- so the wheels come from the
# GitHub release assets instead. Upstream tags releases by commit sha rather
# than by version, hence the sha-looking `release` below; it is a real git tag.
#
# The bump matters for more than freshness: 2.1.0 binds wl_compositor at v6
# (pixelflux/src/lib.rs, `CompositorState::new_v6`, landed 2026-08-12, after the
# 2.0.0 release). v5 was the entire reason the Hyprland desktop has to nest
# inside gst-wayland-display -- aquamarine binds v6 and dies on v5 with
# "invalid version for global wl_compositor (4): expected at most 5, got 6".
# With v6 available, Hyprland should be able to nest directly in pixelflux the
# way niri already does, which also makes it follow the client's resolution
# instead of being pinned by pipeline caps. That simplification is deliberately
# NOT part of this commit -- bump first, verify nothing regresses across all
# five images, then remove the scaffolding separately.
{ lib, stdenv, buildPythonPackage, fetchurl, python, autoPatchelfHook
, libgbm, pixman, libxkbcommon, libva, libdrm, zlib, xorg, libGL, wayland }:
let
  # Upstream tags each release with its commit sha.
  release = "a3290fd";
  wheelUrl = name:
    "https://github.com/selkies-project/pixelflux/releases/download/${release}/${name}";
  wheels = {
    "3.13" = {
      x86_64-linux  = { name = "pixelflux-2.1.0-cp313-cp313-manylinux_2_28_x86_64.whl";  hash = "sha256-ZZqMIgK7+tEOuSXnVlb/cUzxOBancQfZtTAQKwF+B7k="; };
      aarch64-linux = { name = "pixelflux-2.1.0-cp313-cp313-manylinux_2_28_aarch64.whl"; hash = "sha256-cRqhiYiNzFaz7q0AavPeNSIzrnu9e0GpYtYZ6BhXhmw="; };
    };
    "3.14" = {
      x86_64-linux  = { name = "pixelflux-2.1.0-cp314-cp314-manylinux_2_28_x86_64.whl";  hash = "sha256-xDvvO42RUjHCVy4XHipAgKs1vBc1JjR8NaMTZ4x274U="; };
      aarch64-linux = { name = "pixelflux-2.1.0-cp314-cp314-manylinux_2_28_aarch64.whl"; hash = "sha256-w0/XZYxzOHvi+xVL/ScHKYTuloHx6W2MVlGacA49JxI="; };
    };
  };
  pyVer = lib.versions.majorMinor python.version;
  wheel = wheels.${pyVer}.${stdenv.hostPlatform.system}
    or (throw "pixelflux: no wheel for python ${pyVer} on ${stdenv.hostPlatform.system}");
in
buildPythonPackage {
  pname = "pixelflux";
  version = "2.1.0";
  format = "wheel";

  src = fetchurl { inherit (wheel) name hash; url = wheelUrl wheel.name; };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    libgbm pixman libxkbcommon libva libdrm zlib
    xorg.libX11 xorg.libICE xorg.libSM xorg.libXext
  ];
  # Libraries the encoder dlopen()s at runtime rather than linking directly.
  runtimeDependencies = [
    xorg.libX11 xorg.libXext xorg.libXfixes xorg.libXdamage xorg.libXcomposite
    xorg.libXcursor xorg.libXtst xorg.libXi xorg.libXrandr xorg.libXrender
    libGL libva libdrm wayland
  ];

  pythonImportsCheck = [ "pixelflux" ];

  meta = with lib; {
    description = "Selkies screen capture and video encoding module";
    homepage = "https://github.com/selkies-project/pixelflux";
    license = licenses.mpl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
