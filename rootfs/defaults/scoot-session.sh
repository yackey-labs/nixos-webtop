#!/bin/bash
# The scoot session: the status bar, supervised, and deliberately no desktop
# shell. scoot hands this script WAYLAND_DISPLAY (scoot's own socket, not the
# pixelflux parent) and SCOOT_SOCKET; it runs as scoot's `--` command, after
# the config's [autostart] entries.
#
# Wallpaper: scoot's own [wallpaper] config section (one per look, seeded to
# ~/.config/scoot/config.toml by startwm-scoot.sh). scoot starts scootbg
# itself and re-applies the section on every reload, with no [autostart]
# entry and no session script -- so the old scootbg supervision loop and the
# fill/fit output watcher are gone. The look wallpapers are full-bleed
# photographs drawn with mode fill, and scootbg now restores its choice per
# profile (scoot-nested here) across daemon restarts.
#
# Bar: scootbar (scoot's own status bar, same flake input) draws the top bar
# on the Top layer. The config's [autostart] launches it once at startup
# through the scoot-bar-look wrapper (which adds the image's --font store
# path); this script keeps it alive after that, because autostart entries are
# fire-and-forget and this container has no systemd to restart a crashed bar
# (upstream says the same in docs/configuration.md: on the webtop target the
# container is the service manager). Autostart entries always run before this
# script, so the first check -- after a grace pause for exec latency -- sees
# the autostarted bar and never starts a second one.
#
# scootbg takes no exclusive zone (background layer, empty input region), so
# it never shrinks the tiled area. scootbar on the Top layer reserves its
# height (plus margin), which is the "shell is up" signal: the moment it
# maps, `scoot msg outputs` reports usable below rect.
LOG="${XDG_RUNTIME_DIR:-/tmp}/scoot-session.log"

log() { echo "[scoot-session] $* $(date -Is)" >> "$LOG"; }

log "look ${SCOOT_LOOK:-radial-burst}; wallpaper and autostart are scoot's own config now"

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
