# games-on-whales/gst-wayland-display — a micro Wayland compositor exposed as a
# GStreamer source element (`waylanddisplaysrc`). Built on Smithay, same shape
# as pixelflux: it owns a compositor for nested clients and hands raw frames to
# a pipeline, taking input events back the other way.
#
# WHY THIS EXISTS HERE. pixelflux calls Smithay's `CompositorState::new`, which
# binds wl_compositor at version 5. Hyprland's aquamarine binds version 6 and
# dies on the mismatch:
#
#   wl_registry#2: error 0: invalid version for global wl_compositor (2):
#                 expected at most 5, got 6
#   what():  CBackend::create() failed!
#
# This compositor calls `CompositorState::new_v6` (wayland-display-core/src/comp/mod.rs)
# and therefore does not have that limit. pixelflux ships as a manylinux wheel
# with no sdist, so it cannot be patched from this flake; this can be built from
# source, so it is the way to get a v6 parent without vendoring someone else's
# 279-crate build.
#
# Not packaged in nixpkgs. Upstream suggests `cargo cinstall` via cargo-c, but
# the GStreamer plugin is a plain cdylib, so buildRustPackage is enough — the
# C API in c-bindings/ is only needed by Wolf, not by us.
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gst_all_1
, wayland
, wayland-protocols
, libxkbcommon
, libinput
, udev
, libdrm
, libgbm
, libGL
, seatd
, pixman
}:

rustPlatform.buildRustPackage rec {
  pname = "gst-wayland-display";
  version = "0.4.0-unstable-2026-09-10";

  src = fetchFromGitHub {
    owner = "games-on-whales";
    repo = "gst-wayland-display";
    rev = "016b4fc66d62b6a34c37169ecf6d511eef140d7c";
    hash = "sha256-HMimXtNHvZ4iPJzL5PD9n/KdQV0vrrJoLfhT+FOIXTM=";
  };

  # 245 crates, including games-on-whales' own Smithay fork, which is pinned by
  # rev in Cargo.lock so the vendor is reproducible.
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    hash = "sha256-oVTuwmJKfWlk50pZWWAOuTccWMYZo/the1blz65HsrM=";
  };

  # Only the plugin. c-bindings and benchmark are not needed and drag in
  # cargo-c.
  cargoBuildFlags = [ "-p" "gst-plugin-wayland-display" ];
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    # input-event-codes-sys runs bindgen over import.h and needs libclang.
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    wayland
    wayland-protocols
    libxkbcommon
    libinput
    udev
    libdrm
    libgbm
    libGL
    seatd
    pixman
  ];

  # GStreamer discovers plugins by scanning lib/gstreamer-1.0.
  postInstall = ''
    mkdir -p $out/lib/gstreamer-1.0
    for so in $out/lib/libgstwaylanddisplaysrc.so*; do
      [ -e "$so" ] && mv "$so" $out/lib/gstreamer-1.0/
    done
  '';

  meta = with lib; {
    description = "Micro Wayland compositor usable as a GStreamer source (binds wl_compositor v6)";
    homepage = "https://github.com/games-on-whales/gst-wayland-display";
    license = licenses.mit;   # plugin reports MIT/X11; repo LICENSE agrees
    platforms = platforms.linux;
  };
}
