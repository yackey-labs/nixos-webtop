#!/bin/bash
# The scoot session: wallpaper plus bar, and deliberately no desktop shell.
# scoot's config file has no spawn-at-startup table and its `--` takes
# exactly one command, so that one command is this script. scoot hands it
# WAYLAND_DISPLAY (scoot's own socket, not the pixelflux parent) and
# SCOOT_SOCKET.
#
# scootbg (scoot's own wallpaper daemon, from the scoot flake) draws the
# wallpaper -- scoot's peeking ASCII cat, vendored from the scoot repo's
# docs/assets/CatPeeking.png into /defaults/scoot-cat-peeking.png -- on the
# background layer. ashell draws the top bar -- launcher button, workspaces, window
# title, tray, clock, settings -- on the Top layer. fuzzel needs no daemon:
# keybinds and the bar's launcher button spawn it fresh on every use.
#
# scootbg takes no exclusive zone (background layer, empty input region), so
# it never shrinks the tiled area. ashell on the Top layer reserves its
# height, which is the "shell is up" signal: the moment it maps, `scoot msg
# outputs` reports usable below rect.
#
# Not scoot's [wallpaper] config section: that is planned upstream but not
# accepted yet, and scoot ignores the WHOLE config file on an unknown
# section. Until it lands, the session script drives scootbg's CLI.
LOG="${XDG_RUNTIME_DIR:-/tmp}/scoot-session.log"

log() { echo "[scoot-session] $* $(date -Is)" >> "$LOG"; }

WALLPAPER="${WALLPAPER:-/defaults/scoot-cat-peeking.png}"

# scootbg does not restore its wallpaper across a daemon restart yet
# (docs/scootbg/backlog/restore-state.md upstream), so every (re)start drops
# this marker and the watcher below sets the image again on its next tick.
MODE_FILE="${XDG_RUNTIME_DIR:-/tmp}/scoot-session-wallpaper-mode"

supervise_scootbg() {
  while true; do
    rm -f "$MODE_FILE"
    log "starting scootbg daemon"
    scootbg daemon >> "$LOG" 2>&1
    log "scootbg daemon exited ($?); relaunching in 3s"
    sleep 3
  done
}

supervise_scootbg &

# Keep the wallpaper fitted to the output shape. The image is 1672x941
# (~16:9) with the cat peeking in from the RIGHT edge, so `fill`'s centred
# crop is only safe on a screen at least that wide: there it trims top and
# bottom, which is empty. Anything narrower -- a 4:3 or 16:10 browser
# window, a portrait phone -- would crop the sides and cut the cat off, so
# there it uses `fit` instead and pads top/bottom with the
# image's own near-black (#0d0d0d) so the letterbox is invisible. The output
# follows the browser window for the life of the session, so this re-checks
# on a timer rather than setting once. `scootbg set` returns only once the
# image is on screen and fails while no daemon is up, so a failed set leaves
# the marker alone and the next tick retries it. Parsed with awk, not jq:
# this image ships neither jq nor python (see the old noctalia health check
# for why that matters) -- `scoot msg outputs` prints rect width/height
# first, so the first two numbers are the ones wanted.
watch_wallpaper() {
  while true; do
    dims=$(scoot msg outputs 2>/dev/null | awk '/"width"|"height"/ { gsub(/[^0-9]/, ""); print }' | head -n 2)
    W=$(echo "$dims" | sed -n 1p); H=$(echo "$dims" | sed -n 2p)
    if [ -n "$W" ] && [ -n "$H" ]; then
      # Integer cross-multiply: W/H >= 1672/941 without floats.
      if [ $((W * 941)) -ge $((H * 1672)) ]; then want=fill; else want=fit; fi
      if [ "$want" != "$(cat "$MODE_FILE" 2>/dev/null)" ]; then
        if scootbg set "$WALLPAPER" --mode "$want" --fill '#0d0d0d' >> "$LOG" 2>&1; then
          log "wallpaper $want (${W}x${H})"; echo "$want" > "$MODE_FILE"
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
