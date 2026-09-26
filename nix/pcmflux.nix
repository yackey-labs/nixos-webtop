# pcmflux: Selkies' PulseAudio capture + Opus encoder (wheel-only upstream).
# Taken from PyPI, the same wheels selkies 2.0.0 itself was released against
# (pyproject pins pcmflux~=2.1.0).
{ lib, stdenv, buildPythonPackage, fetchurl, python, autoPatchelfHook, xorg }:
let
  wheels = {
    "3.13" = {
      x86_64-linux = { name = "pcmflux-2.1.0-cp313-cp313-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/ec/fe/47d8b69a2434bc1ca76b0456e9ac7ee84719205357d34589d4e878a5ee59/pcmflux-2.1.0-cp313-cp313-manylinux_2_28_x86_64.whl";  hash = "sha256:7c214ce71d529409cde42db9521610b21ddd25d574a29ade9da560db803a0907"; };
      aarch64-linux = { name = "pcmflux-2.1.0-cp313-cp313-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/f8/0d/a91740a0c2ea4ee8ea51e27dcf6a69d11e8cc0390dff6f50ec05268fe4d9/pcmflux-2.1.0-cp313-cp313-manylinux_2_28_aarch64.whl"; hash = "sha256:d2030962d07e1412671f0477667f68dbad91bbd0b131d65678e91b5ec0f42c0b"; };
    };
    "3.14" = {
      x86_64-linux = { name = "pcmflux-2.1.0-cp314-cp314-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/89/95/631255b607ae11f3425d2aace88e041d2d34199c087184483bdba9494095/pcmflux-2.1.0-cp314-cp314-manylinux_2_28_x86_64.whl";  hash = "sha256:eb1afe10e14d3d3888a40aa401acfc116bfa0080ab9b807f16db7f40f1424411"; };
      aarch64-linux = { name = "pcmflux-2.1.0-cp314-cp314-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/e2/48/3257067b3866e4e3910918c8f16dcc2d1fbb13ae7dab588e0840b48584f7/pcmflux-2.1.0-cp314-cp314-manylinux_2_28_aarch64.whl"; hash = "sha256:51b266a766da693f694d4b486876134f1989e5feb8947f091eb22893dc59461c"; };
    };
  };
  pyVer = lib.versions.majorMinor python.version;
  wheel = wheels.${pyVer}.${stdenv.hostPlatform.system}
    or (throw "pcmflux: no wheel for python ${pyVer} on ${stdenv.hostPlatform.system}");
in
buildPythonPackage {
  pname = "pcmflux";
  version = "2.1.0";
  format = "wheel";

  src = fetchurl { inherit (wheel) name url hash; };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib xorg.libX11 xorg.libXext xorg.libICE xorg.libSM ];

  pythonImportsCheck = [ "pcmflux" ];

  meta = with lib; {
    description = "Selkies audio capture and Opus encoding module";
    homepage = "https://github.com/selkies-project/pcmflux";
    license = licenses.mpl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
