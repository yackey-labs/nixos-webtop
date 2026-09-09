# pixelflux: Selkies' X11/Wayland capture + x264/jpeg encoder. Upstream publishes
# only manylinux wheels (no sdist that builds cleanly), so we consume the wheel
# and let autoPatchelf wire it to Nix's libraries.
{ lib, stdenv, buildPythonPackage, fetchurl, python, autoPatchelfHook
, libgbm, pixman, libxkbcommon, libva, libdrm, zlib, xorg, libGL, wayland }:
let
  wheels = {
    "3.13" = {
      x86_64-linux = { name = "pixelflux-2.0.0-cp313-cp313-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/09/b2/79a27f3cbe8c296ecd98770469cc7cda2c8858b2e09b98a1f935d9652188/pixelflux-2.0.0-cp313-cp313-manylinux_2_28_x86_64.whl";  hash = "sha256-kKLYO+VpRY3/NZxd+oPEe7zPVGqgkhT8LtiAbf1CBo0="; };
      aarch64-linux = { name = "pixelflux-2.0.0-cp313-cp313-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/10/74/38f4b2f59b1a98b1f9da4d223fcd88d64194f6dcabf16f61ced77424e72a/pixelflux-2.0.0-cp313-cp313-manylinux_2_28_aarch64.whl"; hash = "sha256-Uu9bmVELTWqJN/evDDM0q8izHRJlSePFJyOZ37OspsA="; };
    };
    "3.14" = {
      x86_64-linux = { name = "pixelflux-2.0.0-cp314-cp314-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/94/da/b4b134d12f46fadc5edc94f778ac324ca6ab02b5b9be91466f95251e6f14/pixelflux-2.0.0-cp314-cp314-manylinux_2_28_x86_64.whl";  hash = "sha256:7c501d184fba79746ca63118b5cc462851b7cad217094e11a011696b3bfa3953"; };
      aarch64-linux = { name = "pixelflux-2.0.0-cp314-cp314-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/01/eb/899b089ad868a4ded2e726df93cfe0914ac9daa89774809ddd65c4829b0d/pixelflux-2.0.0-cp314-cp314-manylinux_2_28_aarch64.whl"; hash = "sha256:033afea1c4308416460249b554bd717731a62b7ae7b676357069eb294f723c24"; };
    };
  };
  pyVer = lib.versions.majorMinor python.version;
  wheel = wheels.${pyVer}.${stdenv.hostPlatform.system}
    or (throw "pixelflux: no wheel for python ${pyVer} on ${stdenv.hostPlatform.system}");
in
buildPythonPackage {
  pname = "pixelflux";
  version = "2.0.0";
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
