#!/bin/bash
# Minimal dev session for the scoot-dev image: no bar, no wallpaper, no
# launcher daemon. One foot window so the empty desktop has a terminal in it;
# everything else (including the tools under test) spawns from keybinds
# (Alt+Return foot, Alt+d fuzzel) or `scoot msg action spawn`.
#
# scoot's config has no spawn-at-startup, and its `--` takes exactly one
# command, so that one command is this script. scoot hands it WAYLAND_DISPLAY
# (scoot's own socket, not the pixelflux parent) and SCOOT_SOCKET.
LOG="${XDG_RUNTIME_DIR:-/tmp}/scoot-session-dev.log"

log() { echo "[scoot-session-dev] $* $(date -Is)" >> "$LOG"; }

log "starting foot"
foot >> "$LOG" 2>&1 &
log "foot pid $!"

# Stay alive for the life of the compositor; the foot above is convenience,
# not supervision -- closing it must not end the session.
exec sleep infinity
