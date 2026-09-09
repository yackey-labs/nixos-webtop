# pcmflux: Selkies' PulseAudio capture + Opus encoder (wheel-only upstream).
{ lib, stdenv, buildPythonPackage, fetchurl, python, autoPatchelfHook, xorg }:
let
  wheels = {
    "3.13" = {
      x86_64-linux = { name = "pcmflux-2.0.0-cp313-cp313-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/6d/e5/ab80cd4d0b111bcda3cfe211a2f84b961dabaea8e1c9fb8e9118ca533e89/pcmflux-2.0.0-cp313-cp313-manylinux_2_28_x86_64.whl";  hash = "sha256-KOwrMzJwhbANnFdz6Ak7hSVoN7ygMlexZ4acmrRYSrE="; };
      aarch64-linux = { name = "pcmflux-2.0.0-cp313-cp313-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/0f/9b/e4bf1d7da63951e3ca5c9dc57a6e0e41e0275b4451d55d7bb63bfe78b39b/pcmflux-2.0.0-cp313-cp313-manylinux_2_28_aarch64.whl"; hash = "sha256-wJJBmiKLqSBYsrGYLKYZAAbqj+IHRj3N/PalYyxXvU0="; };
    };
    "3.14" = {
      x86_64-linux = { name = "pcmflux-2.0.0-cp314-cp314-manylinux_2_28_x86_64.whl";  url = "https://files.pythonhosted.org/packages/fd/69/99bb9d02fe925a0f38d9359e0761a9d38d831c293eba71654f3d29f13acf/pcmflux-2.0.0-cp314-cp314-manylinux_2_28_x86_64.whl";  hash = "sha256:050a8c7d7c099ee363279f085cab65e5f9891dc6ab9481a3edf64a901d276352"; };
      aarch64-linux = { name = "pcmflux-2.0.0-cp314-cp314-manylinux_2_28_aarch64.whl"; url = "https://files.pythonhosted.org/packages/78/28/a4209023b9d3420814e3d79dc179ef11eddf89b15bc1a1b15eaeb473967f/pcmflux-2.0.0-cp314-cp314-manylinux_2_28_aarch64.whl"; hash = "sha256:d19c1f2c9773eb3e185f92e34ff331cfb5d2546d07494332f32e8aaa8f41f647"; };
    };
  };
  pyVer = lib.versions.majorMinor python.version;
  wheel = wheels.${pyVer}.${stdenv.hostPlatform.system}
    or (throw "pcmflux: no wheel for python ${pyVer} on ${stdenv.hostPlatform.system}");
in
buildPythonPackage {
  pname = "pcmflux";
  version = "2.0.0";
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
