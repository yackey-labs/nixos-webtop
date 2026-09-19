#!/bin/bash
# The scoot session: everything that should be running alongside the
# compositor. scoot's config file has no spawn-at-startup table and its `--`
# takes exactly one command, so that one command is this script. scoot hands
# it WAYLAND_DISPLAY (scoot's own socket, not the pixelflux parent) and
# SCOOT_SOCKET.
#
# noctalia-shell (Quickshell) provides the bar, launcher, notifications,
# wallpaper, control center and lock screen, exactly as in the niri image.
# It talks to scoot through wlr-layer-shell-v1 and ext-workspace-v1; there is
# no compositor-specific integration to configure.
LOG="${XDG_RUNTIME_DIR:-/tmp}/noctalia.log"

# Plain crash supervision -- unlike rootfs/defaults/noctalia-start.sh (niri),
# there is no first-frame freeze to detect and retry around. That workaround
# exists because niri's nested backend only sends frame callbacks when the
# parent drives it, so a Quickshell started before any browser connected
# blocked forever during initial exposure. scoot's nested backend runs its
# own frame timer and never blocks on the host, so the shell maps its layer
# surfaces whether or not anyone is streaming yet.
while true; do
  # Stale Quickshell IPC paths from a previous run make it refuse to start.
  rm -rf "${XDG_RUNTIME_DIR}/quickshell/by-path" 2>/dev/null
  echo "[scoot-session] starting noctalia-shell $(date -Is)" >> "$LOG"
  noctalia-shell >> "$LOG" 2>&1
  echo "[scoot-session] noctalia-shell exited ($?) $(date -Is)" >> "$LOG"
  sleep 3
done
