#!/bin/bash
# Dev flavour of startwm-scoot.sh: identical nesting, but the session is
# scoot-session-dev.sh (foot only -- no bar, no wallpaper) instead of the
# ashell + awww session. Those two are what this image exists to replace
# (scootbar, scootbg), so shipping them here would test against the thing
# being replaced.
ulimit -c 0
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XDG_CURRENT_DESKTOP=scoot
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
# scoot has NO XWayland -- there is no X11 fallback to offer, so nothing is
# told to look for one. GDK_BACKEND=wayland,x11 would leave a GTK app that
# fails on Wayland retrying against a :1 that is not part of this session.
export GDK_BACKEND=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
# Deliberately NOT set: vblank_mode=0 (see startwm-scoot.sh -- pixman
# present() drops rather than blocking, so there is nothing to stall on).

W="${SELKIES_MANUAL_WIDTH:-1280}"; H="${SELKIES_MANUAL_HEIGHT:-800}"
[ "$W" = "0" ] && W=1280
[ "$H" = "0" ] && H=800

exec scoot --nested --width "$W" --height "$H" -- /defaults/scoot-session-dev.sh
