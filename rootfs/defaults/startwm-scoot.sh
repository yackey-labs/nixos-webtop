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
#
# XWayland stays opt-IN upstream too ([xwayland] enabled = false): it costs a
# whole extra server process (~55 MB RSS idle) plus the X userland this image
# deliberately drops (x11 = false), and any X client can keylog by design.
# Everything in this image is Wayland-native, so there is nothing to gain.
export GDK_BACKEND=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
# Deliberately NOT set: vblank_mode=0. The niri and Hyprland images need it
# because their nested backends block in eglSwapBuffers until the parent
# sends a frame callback, and pixelflux only renders while a browser is
# attached. scoot renders with pixman into wl_shm buffers on its own 16 ms
# timer and its present() drops a frame rather than blocking when the host
# has released neither buffer, so there is nothing to stall on.

# ── The look ─────────────────────────────────────────────────────────────
# SCOOT_LOOK seeding lives in /defaults/scoot-look-seed.sh, shared with the
# VNC image's startwm script: one copy, so the four looks cannot drift apart
# between the two images.
# shellcheck source=/dev/null
. /defaults/scoot-look-seed.sh

# Every start, not just seeding ones: a restarted container keeps its seeded
# files but gets a fresh environment, and scoot inherits this one -- so the
# bar's exec modules resolve load.sh/cpu.sh through it either way.
export PATH="$HOME/.config/scoot/bin:$PATH"

# The size to come up at. scoot follows the host's size for the life of the
# session now (scoot-sh/scoot#144, fixed upstream), so a later browser resize
# reflows rather than letterboxing, and this is only the starting point --
# what the desktop looks like before anyone has connected, and what it falls
# back to if pixelflux answers the first configure with 0x0 ("you choose").
W="${SELKIES_MANUAL_WIDTH:-1280}"; H="${SELKIES_MANUAL_HEIGHT:-800}"
[ "$W" = "0" ] && W=1280
[ "$H" = "0" ] && H=800

exec scoot --nested --width "$W" --height "$H" -- /defaults/scoot-session.sh
