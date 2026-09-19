#!/bin/bash
# scoot nested inside pixelflux's compositor (parent is WAYLAND_DISPLAY=wayland-1).
#
# scoot has no backend auto-detection: --headless, --nested and --tty are
# explicit, so the nesting is spelled out here rather than inferred from
# WAYLAND_DISPLAY the way niri's winit backend and Hyprland's aquamarine do.
ulimit -c 0
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XDG_CURRENT_DESKTOP=scoot
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
# scoot has NO XWayland -- there is no X11 fallback to offer, so nothing is
# told to look for one. GDK_BACKEND=wayland,x11 would leave a GTK app that
# fails on Wayland retrying against a :1 that is not part of this session,
# and ELECTRON_OZONE_PLATFORM_HINT=auto would let Chromium pick X11.
export GDK_BACKEND=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
# Deliberately NOT set: vblank_mode=0. The niri and Hyprland images need it
# because their nested backends block in eglSwapBuffers until the parent
# sends a frame callback, and pixelflux only renders while a browser is
# attached. scoot renders with pixman into wl_shm buffers on its own 16 ms
# timer and its present() drops a frame rather than blocking when the host
# has released neither buffer, so there is nothing to stall on.

# scoot applies the host's size from its FIRST xdg_surface configure and
# never resizes again, so the session runs at whatever it starts at -- later
# browser resizes are letterboxed by pixelflux, not reflowed. Start at the
# requested resolution rather than scoot's own 1280x720 default.
W="${SELKIES_MANUAL_WIDTH:-1280}"; H="${SELKIES_MANUAL_HEIGHT:-800}"
[ "$W" = "0" ] && W=1280
[ "$H" = "0" ] && H=800

exec scoot --nested --width "$W" --height "$H" -- /defaults/scoot-session.sh
