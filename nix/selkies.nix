# The Selkies backend (websockets mode). Pinned to the upstream 2.0.0 release,
# which brings the gaming mode (pointer + keyboard lock) the Mac Cmd-as-Super
# case needs, and a rewritten capture setup where the jpeg-encoder
# use_openh264 crash the previous pin had is gone (so the patch that fixed it
# is gone too).
{ lib, python3, selkiesSrc, wayland, libglvnd, mesa, libgbm, libva, libdrm, libxkbcommon, pixman, xorg }:
python3.pkgs.buildPythonApplication {
  pname = "selkies";
  version = "2.0.0";
  pyproject = true;

  src = selkiesSrc;

  build-system = with python3.pkgs; [ setuptools wheel ];

  dependencies = with python3.pkgs; [
    websockets gputil prometheus-client msgpack pynput psutil watchdog pillow
    python-xlib pixelflux pcmflux xkbcommon distro pulsectl pasimple
    # WebRTC mode deps (kept so --mode=webrtc works too)
    aioice av cffi cryptography google-crc32c pyee pylibsrtp pyopenssl aiohttp aiofiles
    # New in 2.0.0: microphone uplink, ICE/DNS, GPU stats, main loop.
    pulsectl-asyncio dnspython uvloop nvidia-ml-py
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
