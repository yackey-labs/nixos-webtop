# The Selkies backend (websockets mode). Same commit linuxserver pins.
{ lib, python3, selkiesSrc, wayland, libglvnd, mesa, libgbm, libva, libdrm, libxkbcommon, pixman, xorg }:
python3.pkgs.buildPythonApplication {
  pname = "selkies";
  version = "1.6.2-unstable-2026";
  pyproject = true;

  src = selkiesSrc;

  postPatch = ''
    # Direct-URL dependency is not allowed in Nix builds; we supply the fork ourselves.
    substituteInPlace pyproject.toml \
      --replace-fail '"python-xlib @ https://github.com/selkies-project/python-xlib/archive/master.zip",' '"python-xlib",'
  '';

  build-system = with python3.pkgs; [ setuptools wheel ];

  dependencies = with python3.pkgs; [
    websockets gputil prometheus-client msgpack pynput psutil watchdog pillow
    python-xlib pixelflux pcmflux xkbcommon distro pulsectl pasimple
    # WebRTC mode deps (kept so --mode=webrtc works too)
    aioice av cffi cryptography google-crc32c pyee pylibsrtp pyopenssl aiohttp aiofiles
  ];

  pythonRelaxDeps = true;
  doCheck = false;

  # pixelflux's embedded Smithay compositor and the X11 capture path dlopen()
  # these by soname (libwayland-server.so.0, libEGL.so.1, libX11.so.6, ...),
  # which autoPatchelf cannot see. Make them resolvable for the selkies process.
  makeWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
      wayland libglvnd mesa libgbm libva libdrm libxkbcommon pixman
      xorg.libX11 xorg.libXext xorg.libXfixes xorg.libXdamage xorg.libXcomposite
      xorg.libXcursor xorg.libXtst xorg.libXi xorg.libXrandr xorg.libXrender xorg.libxcb
    ]}"
  ];

  meta = with lib; {
    description = "Low-latency Linux remote desktop streaming platform";
    homepage = "https://github.com/selkies-project/selkies";
    license = licenses.mpl20;
    mainProgram = "selkies";
  };
}
