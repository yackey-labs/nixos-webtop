#!/bin/bash
# The scoot VNC session: the status bar, supervised, and deliberately no
# desktop shell -- the same shape as scoot-session.sh in the Selkies image
# (the bar is a plain layer-shell client, the launcher spawns fresh per use,
# the wallpaper is scoot's own [wallpaper] section driving scootbg).
#
# One VNC-only job on top: publish WAYLAND_DISPLAY (scoot's own socket, set
# for this script as scoot's `--` command) where the wayvnc s6 service can
# read it. s6 services do not inherit this environment, so a file under
# XDG_RUNTIME_DIR is the handoff.
LOG="${XDG_RUNTIME_DIR:-/tmp}/scoot-session.log"

log() { echo "[scoot-session-vnc] $* $(date -Is)" >> "$LOG"; }

log "look ${SCOOT_LOOK:-radial-burst}; wallpaper and autostart are scoot's own config now"

if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  echo "$WAYLAND_DISPLAY" > "$XDG_RUNTIME_DIR/scoot-display"
  log "published WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
else
  log "ERROR: WAYLAND_DISPLAY or XDG_RUNTIME_DIR unset; wayvnc will have nothing to attach to"
fi

# Grace for the [autostart] bar to appear before the first check.
sleep 5

while true; do
  if pgrep -x scootbar >/dev/null 2>&1; then
    sleep 10
  else
    log "starting scoot-bar-look"
    scoot-bar-look >> "$LOG" 2>&1
    log "bar exited ($?); relaunching in 3s"
    sleep 3
  fi
done
