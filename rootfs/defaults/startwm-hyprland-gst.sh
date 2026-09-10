#!/bin/bash
# Hyprland nested inside games-on-whales' gst-wayland-display instead of
# pixelflux.
#
# WHY: pixelflux calls Smithay's CompositorState::new, binding wl_compositor at
# version 5. Hyprland's aquamarine binds version 6 and dies:
#   wl_registry#2: error 0: invalid version for global wl_compositor (2):
#                 expected at most 5, got 6
#   what():  CBackend::create() failed!
# gst-wayland-display calls CompositorState::new_v6, so it has no such limit.
#
# pixelflux still runs and owns wayland-1 (it is what Selkies streams). This
# script starts a SECOND compositor via GStreamer, which takes the next free
# socket, and points Hyprland at that. Streaming still shows pixelflux's
# surface; this build exists to answer whether Hyprland starts at all.
ulimit -c 0
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1
export vblank_mode=0

# gst-wayland-display dlopen()s libEGL.so.1 by soname at runtime. A Nix image
# keeps its libraries under /nix/store and resolves them through each binary's
# RPATH; /usr/lib is a symlink farm the loader does not search by default, so
# the dlopen fails even though the library is sitting right there:
#   Failed to load LibEGL: DlOpen { "libEGL.so.1: cannot open shared object file" }
# Append rather than overwrite: the NVIDIA shim in rootfs/init may already have
# put /usr/local/lib here.
export LD_LIBRARY_PATH="/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# gst-wayland-display needs a real EGL stack even on its software path: with no
# render node it panics in smithay::backend::egl::ffi rather than degrading to
# Pixman the way pixelflux does. Prefer the real node, fall back to the
# documented software mode.
RENDER_NODE="${DRI_NODE:-/dev/dri/renderD128}"
if [ ! -e "$RENDER_NODE" ]; then
  echo "[hypr-gst] no render node at $RENDER_NODE; falling back to software"
  RENDER_NODE=software
fi
echo "[hypr-gst] starting gst-wayland-display with render-node=$RENDER_NODE"

before="$(ls "${XDG_RUNTIME_DIR}"/wayland-* 2>/dev/null | tr '\n' ' ')"
# Render Hyprland's compositor INTO pixelflux's as a fullscreen client, so
# Selkies streams it with no changes to the streaming stack. waylandsink
# connects to WAYLAND_DISPLAY as it stands now -- wayland-1, pixelflux's socket,
# set by the de service -- because this runs before the export below.
#
# Input works because GStreamer propagates Navigation events UPSTREAM from the
# sink, and waylanddisplaysrc handles them (imp.rs: NavigationEvent::MouseMove,
# KeyPress, ...). So clicks and keys land in Hyprland rather than stopping at
# the surface showing it.
gst-launch-1.0 waylanddisplaysrc render-node="$RENDER_NODE" \
  ! videoconvert ! waylandsink fullscreen=true \
  > "${XDG_RUNTIME_DIR}/gst-wayland-display.log" 2>&1 &
GST_PID=$!

# Wait for it to publish a socket that did not exist a moment ago.
SOCK=""
for _ in $(seq 1 30); do
  sleep 1
  kill -0 "$GST_PID" 2>/dev/null || { echo "[hypr-gst] compositor died:"; tail -20 "${XDG_RUNTIME_DIR}/gst-wayland-display.log"; exit 1; }
  for s in "${XDG_RUNTIME_DIR}"/wayland-*; do
    case "$s" in *.lock) continue;; esac
    [ -S "$s" ] || continue
    case " $before " in *" $s "*) continue;; esac
    SOCK="$(basename "$s")"; break 2
  done
done

if [ -z "$SOCK" ]; then
  echo "[hypr-gst] gst-wayland-display published no socket in 30s:"
  tail -20 "${XDG_RUNTIME_DIR}/gst-wayland-display.log"
  exit 1
fi

echo "[hypr-gst] compositor is on $SOCK; starting Hyprland nested in it"
export WAYLAND_DISPLAY="$SOCK"
exec Hyprland
