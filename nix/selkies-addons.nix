# Gamepad support helpers from the selkies repo: an LD_PRELOAD input
# interposer and a fake libudev so browsers see virtual /dev/input/js* devices.
# (Upstream renamed js-interposer to input-interposer in 2.0.0 and ships a
# selkies_joystick_interposer.so symlink for old preload paths; we install the
# same symlink so SELKIES_INTERPOSER and the LD_PRELOAD in rootfs/init keep
# working untouched.)
{ lib, stdenv, selkiesSrc }:
stdenv.mkDerivation {
  pname = "selkies-addons";
  version = "2.0.0";
  src = selkiesSrc;
  buildPhase = ''
    runHook preBuild
    ( cd addons/input-interposer && make )
    ( cd addons/fake-udev && make )
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp addons/input-interposer/selkies_input_interposer.so $out/lib/
    ln -s selkies_input_interposer.so $out/lib/selkies_joystick_interposer.so
    cp addons/fake-udev/libudev.so.1.0.0-fake $out/lib/
    runHook postInstall
  '';
}
