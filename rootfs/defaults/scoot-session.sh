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

log() { echo "[scoot-session] $* $(date -Is)" >> "$LOG"; }

# Has the shell mapped anything that reserves screen space?
#
# scoot answers this natively: an output's `usable` rect is the full rect
# minus whatever layer-shell exclusive zones have been taken, so the moment
# noctalia's bar maps, usable shrinks below rect. That is a direct read of
# the thing we actually care about -- the niri image has to grep `niri msg
# layers` for a namespace instead.
shell_mapped() {
  # scoot answers this natively: an output's `usable` rect is the full rect
  # minus whatever layer-shell exclusive zones have been taken, so the moment
  # noctalia's bar maps, usable shrinks below rect. That is a direct read of
  # the thing we actually care about -- the niri image has to grep `niri msg
  # layers` for a namespace instead.
  #
  # Parsed with awk, not jq or python: this image ships NEITHER (checked in
  # the running container -- selkies' interpreter is inside its own wrapper,
  # not on PATH). A health check calling a missing binary always reports
  # "not mapped", which would kill and relaunch a perfectly healthy shell
  # every 90 seconds, forever.
  #
  # `scoot msg outputs` prints each output as rect{x,y,width,height} then
  # scale then usable{x,y,width,height}, so the width/height values arrive in
  # the order rect.w, rect.h, usable.w, usable.h. Any edge a bar reserves
  # changes one of the latter two. scoot is single-output today (multi-output
  # is on its roadmap); a second output would interleave and want a real
  # parser here.
  scoot msg outputs 2>/dev/null | awk '
    /"width"|"height"/ { gsub(/[^0-9]/, ""); v[n++] = $0 }
    END { exit (n >= 4 && (v[0] != v[2] || v[1] != v[3])) ? 0 : 1 }
  '
}

# WHY THIS RETRIES.
#
# noctalia's FIRST launch against a fresh /config wedges partway through
# start-up: it loads its config, scans for plugins, and then stops -- no
# fonts, no wallpaper scan, no layer surfaces, and settingsVersion left at 0
# where a healthy config reaches 59. Observed on the cluster on first boot,
# and it does not resolve on its own (left for 12 minutes). Killing it clears
# it: the second run walks straight past that point and maps the bar.
#
# This is NOT the frame-callback freeze the niri image's noctalia-start.sh
# describes. That one does not apply here and was checked rather than
# assumed: scoot drives its own 16 ms frame timer and its nested present()
# drops a frame instead of blocking, so clients get frame callbacks with no
# browser attached -- ghostty renders and fuzzel maps an overlay layer
# surface on an idle session. The failure is inside noctalia's own start-up,
# and the wrapper is here for that.
while true; do
  if pgrep -f quickshell >/dev/null 2>&1; then
    if shell_mapped; then
      sleep 15            # healthy: bar/wallpaper mapped
      continue
    fi
    log "quickshell running but nothing mapped; restarting"
    # By PID, and NOT `pkill -x quickshell`: the process is a wrapper whose
    # comm is truncated to `.quickshell-wra`, so an exact-name match finds
    # nothing and the kill silently does nothing at all.
    pkill -f quickshell
    sleep 2
  fi

  # Stale Quickshell IPC paths from a previous run make it refuse to start.
  rm -rf "${XDG_RUNTIME_DIR}/quickshell/by-path" 2>/dev/null
  log "starting noctalia-shell"
  noctalia-shell >> "$LOG" 2>&1 &
  NPID=$!

  # First launch is slow even when it works -- config generation, plugin
  # scan, and a fontconfig warm-up that loads ~300 fonts -- so this waits
  # well past that before calling it wedged.
  for _ in $(seq 1 90); do
    sleep 1
    kill -0 "$NPID" 2>/dev/null || break
    if shell_mapped; then break; fi
  done

  if shell_mapped; then
    log "noctalia mapped its shell; supervising"
    wait "$NPID"
    log "noctalia exited ($?); will relaunch"
  else
    log "noctalia did not map a shell in 90s; killing and retrying"
    kill "$NPID" 2>/dev/null
    pkill -f quickshell 2>/dev/null
  fi
  sleep 3
done
