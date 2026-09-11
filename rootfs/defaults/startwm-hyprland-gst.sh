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
# socket, and points Hyprland at that. waylandsink then renders that nested
# session back into pixelflux's surface as a fullscreen client, so Selkies
# streams it unchanged.
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
#
# That is only true of a sink that actually ORIGINATES those events, which
# waylandsink does not -- it implements GstVideoOverlay and nothing else, never
# binds wl_seat, and so never turns the pointer and keyboard input its surface
# receives into navigation events. With waylandsink the desktop rendered
# perfectly and was completely dead: hyprctl cursorpos pinned at 960,540
# forever, no keybinds, no clicks. Wolf does not hit this because it injects
# input straight into the compositor from Moonlight instead of through a sink.
#
# glimagesink does implement GstNavigation, and gst-gl's Wayland backend binds
# wl_seat and adds both a wl_pointer and a wl_keyboard listener
# (gstglwindow_wayland_egl.c), feeding gst_gl_window_send_mouse_event /
# send_key_event. That is exactly the event stream waylanddisplaysrc is already
# written to consume.
# The caps between the source and the first queue are NOT optional. Without
# them waylanddisplaysrc never negotiates a size: it creates its output as
#   Creating new Output name="HEADLESS-1" physical=PhysicalProperties {
#       size: Size { w: 0, h: 0 }, make: "Virtual", model: "Wolf" }
# and Hyprland, nested in it, reports `1x1@60.00` with zero windows mapped --
# swaybg, waybar, mako and xwayland-satellite all run but map nothing. The
# allocator then segfaults on the first `Creating DMA buffer`, and downstream
# waylandsink is handed a 65536-byte system-memory buffer it cannot wrap:
#   waylandsink0: buffer ... size 65536 ... flags 0x4000 cannot have a wl_buffer
# Visible result is a white rectangle on a black field. games-on-whales' Wolf
# sets the same caps on this element for the same reason.
WD_WIDTH="${WD_WIDTH:-1920}"
WD_HEIGHT="${WD_HEIGHT:-1080}"
WD_FPS="${WD_FPS:-60}"
echo "[hypr-gst] pinning virtual output to ${WD_WIDTH}x${WD_HEIGHT}@${WD_FPS}"

# --no-fault matters as much as the caps. gst-launch installs a fault handler
# that, on SIGSEGV, tries to exec gdb and -- when gdb is absent, as it is here --
# parks the process spinning forever:
#   Caught SIGSEGV / exec gdb failed: No such file or directory / Spinning.
# The PID stays alive, so s6 sees a healthy service and never restarts it, and
# the pod sits 1/1 Ready while rendering nothing. With --no-fault the crash
# actually kills the process and the supervision below takes over.
# force-aspect-ratio=true, NOT false. The compositor is pinned to WD_WIDTH x
# WD_HEIGHT, so when Selkies resizes its output to match the client -- a phone
# in portrait reports something like 1290x2232 -- a 16:9 desktop has to go into
# a 9:19.5 window. With force-aspect-ratio=false that is a stretch, which is the
# "everything looks smushed" report from a phone. With it true the desktop is
# letterboxed instead: smaller, but the right shape and readable.
#
# videoconvert is kept ahead of the sink deliberately. glimagesink embeds
# glupload/glcolorconvert and could take the DMA-BUF directly, which would be
# the faster path, but the converted route is the one already proven to render
# here -- correctness of the input path first, zero-copy as a follow-up.
gst-launch-1.0 --no-fault waylanddisplaysrc render-node="$RENDER_NODE" \
  ! video/x-raw,width=${WD_WIDTH},height=${WD_HEIGHT},framerate=${WD_FPS}/1 \
  ! queue max-size-buffers=3 leaky=downstream ! videoconvert \
  ! queue max-size-buffers=3 leaky=downstream \
  ! glimagesink handle-events=true force-aspect-ratio=true \
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

# Do NOT exec Hyprland. The compositor it is nested in is a sibling process, and
# if that dies Hyprland keeps running against a dead socket -- which is exactly
# how this failed silently before: gst was gone, Hyprland was up, the service
# looked healthy. Supervise both and exit non-zero the moment either goes, so s6
# tears the session down and restarts it as a unit.
Hyprland &
HYPR_PID=$!

wait -n "$GST_PID" "$HYPR_PID"
STATUS=$?

if kill -0 "$GST_PID" 2>/dev/null; then
  echo "[hypr-gst] Hyprland exited (status $STATUS); stopping compositor"
  kill "$GST_PID" 2>/dev/null
else
  echo "[hypr-gst] compositor died (status $STATUS); stopping Hyprland. Last log:"
  tail -30 "${XDG_RUNTIME_DIR}/gst-wayland-display.log"
  kill "$HYPR_PID" 2>/dev/null
fi
wait
exit "$STATUS"
