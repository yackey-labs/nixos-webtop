# pixelflux: Selkies' X11/Wayland capture + video encoder. Upstream publishes
# only manylinux wheels (no sdist that builds cleanly), so we consume the wheel
# and let autoPatchelf wire it to Nix's libraries. Taken from PyPI, the same
# wheels selkies 2.0.0 itself was released against (pyproject pins
# pixelflux~=2.1.0).
#
# 2.1.0 matters for more than freshness: it binds wl_compositor at v6
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
  wheels = {
    "3.13" = {
      x86_64-linux  = { name = "pixelflux-2.1.0-cp313-cp313-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/a6/95/4374970992f0f292184c6532e97bc18f48f3430fb5d27574f77bdf9b696b/pixelflux-2.1.0-cp313-cp313-manylinux_2_28_x86_64.whl";  hash = "sha256:43d47574e52f485d86b4b3d0f56c6bcf160e99ebc658cb59d7a096e6ee0ca1a0"; };
      aarch64-linux = { name = "pixelflux-2.1.0-cp313-cp313-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/f4/0b/5dff1fa8ea3d282bc438fa32b2062251ddb0f29a8ec0fd6e65424bc57deb/pixelflux-2.1.0-cp313-cp313-manylinux_2_28_aarch64.whl"; hash = "sha256:7e4f0b94f51bb89f7fa3f152d2657d069382f29d04058c4dc7e7fb3924a81437"; };
    };
    "3.14" = {
      x86_64-linux  = { name = "pixelflux-2.1.0-cp314-cp314-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/55/e2/b3d4ebf6180ed84c520aafe204a36fcda28d60559caab2e3be889d4eadef/pixelflux-2.1.0-cp314-cp314-manylinux_2_28_x86_64.whl";  hash = "sha256:a4f3fb52f5e2dec03c9b1539ac750c19d43a04d00b4de744054260292d1da0f2"; };
      aarch64-linux = { name = "pixelflux-2.1.0-cp314-cp314-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/8e/ab/964a7cdb7b6add178c97acb5fbc4b187df14fcf981a88167e065e7c2121b/pixelflux-2.1.0-cp314-cp314-manylinux_2_28_aarch64.whl"; hash = "sha256:9960c804454265d7e25935ef7675032909781a032b50789287c04b1797ebee04"; };
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

  src = fetchurl { inherit (wheel) name url hash; };

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
