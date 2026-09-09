# Gamepad support helpers from the selkies repo: an LD_PRELOAD joystick
# interposer and a fake libudev so browsers see virtual /dev/input/js* devices.
{ lib, stdenv, selkiesSrc }:
stdenv.mkDerivation {
  pname = "selkies-addons";
  version = "unstable-2026";
  src = selkiesSrc;
  buildPhase = ''
    runHook preBuild
    ( cd addons/js-interposer && $CC -shared -fPIC -o selkies_joystick_interposer.so joystick_interposer.c -ldl )
    ( cd addons/fake-udev && make )
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp addons/js-interposer/selkies_joystick_interposer.so $out/lib/
    cp addons/fake-udev/libudev.so.1.0.0-fake $out/lib/
    runHook postInstall
  '';
}
