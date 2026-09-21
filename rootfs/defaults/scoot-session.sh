#!/bin/bash
# The scoot session: wallpaper plus bar, and deliberately no desktop shell.
# scoot's config file has no spawn-at-startup table and its `--` takes
# exactly one command, so that one command is this script. scoot hands it
# WAYLAND_DISPLAY (scoot's own socket, not the pixelflux parent) and
# SCOOT_SOCKET.
#
# awww-daemon draws the wallpaper (scoot's own cat logo, vendored from the
# scoot repo's docs/assets/logo.png into /defaults/scoot-cat.png) on the
# background layer. ashell draws the top bar -- launcher button, workspaces,
# window title, tray, clock, settings -- on the Top layer. fuzzel needs no
# daemon: keybinds and the bar's launcher button spawn it fresh on every use.
#
# awww takes no exclusive zone (background layer, empty input region), so it
# never shrinks the tiled area. ashell on the Top layer reserves its height,
# which is the "shell is up" signal: the moment it maps, `scoot msg outputs`
# reports usable below rect.
LOG="${XDG_RUNTIME_DIR:-/tmp}/scoot-session.log"

log() { echo "[scoot-session] $* $(date -Is)" >> "$LOG"; }

WALLPAPER="${WALLPAPER:-/defaults/scoot-cat.png}"

supervise_awww() {
  while true; do
    log "starting awww-daemon"
    awww-daemon >> "$LOG" 2>&1
    log "awww-daemon exited ($?); relaunching in 3s"
    sleep 3
  done
}

supervise_awww &

# The daemon publishes its control socket asynchronously; wait for it before
# the first image, else the set is refused and the session sits on the flat
# background color. Re-setting later is always possible with another
# `awww img` -- nothing here needs to repeat it.
for _ in $(seq 1 30); do
  if awww img "$WALLPAPER" >> "$LOG" 2>&1; then log "wallpaper set"; break; fi
  sleep 1
done

while true; do
  log "starting ashell"
  ashell >> "$LOG" 2>&1
  log "ashell exited ($?); relaunching in 3s"
  sleep 3
done
