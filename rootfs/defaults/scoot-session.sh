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

# Keep the wallpaper fitted to the output shape. The logo is 3:2 landscape:
# cropped fills a landscape screen edge to edge, but on a portrait phone it
# would slice the cat in half, so there it fits the width instead and pads
# top/bottom with the background color to match scoot's flat clear color.
# The output follows the browser window for the life of the session, so this
# re-checks on a timer rather than setting once. `--transition-type none`
# keeps a re-set instant instead of replaying the fade, and a failed set
# leaves MODE alone so the next tick retries it. Parsed with awk, not jq:
# this image ships neither jq nor python (see the old noctalia health check
# for why that matters) -- `scoot msg outputs` prints rect width/height
# first, so the first two numbers are the ones wanted.
MODE=""
watch_wallpaper() {
  while true; do
    dims=$(scoot msg outputs 2>/dev/null | awk '/"width"|"height"/ { gsub(/[^0-9]/, ""); print }' | head -n 2)
    W=$(echo "$dims" | sed -n 1p); H=$(echo "$dims" | sed -n 2p)
    if [ -n "$W" ] && [ -n "$H" ]; then
      if [ "$H" -gt "$W" ]; then want=fit; else want=crop; fi
      if [ "$want" != "$MODE" ]; then
        if awww img --resize "$want" --fill-color 000000ff --transition-type none "$WALLPAPER" >> "$LOG" 2>&1; then
          log "wallpaper $want (${W}x${H})"; MODE="$want"
        fi
      fi
    fi
    sleep 15
  done
}

watch_wallpaper &

while true; do
  log "starting ashell"
  ashell >> "$LOG" 2>&1
  log "ashell exited ($?); relaunching in 3s"
  sleep 3
done
