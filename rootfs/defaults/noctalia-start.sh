#!/bin/bash
# Supervise noctalia-shell (Quickshell).
#
# Quickshell uses Qt's threaded Wayland render loop, which blocks on its first
# frame callback. niri runs here as a *nested* winit client of pixelflux's
# compositor, and pixelflux only drives rendering (and thus frame callbacks)
# while a browser is actually streaming. So a noctalia started before the first
# client connects freezes during initial exposure and never maps its layer
# surfaces, even after a client later connects.
#
# This wrapper works around that: it (re)starts noctalia and, if the shell fails
# to map any layer-shell surface within a grace period, kills it and retries.
# Once a browser is connected the attempt succeeds and the loop just watches it.
LOG="${XDG_RUNTIME_DIR:-/tmp}/noctalia.log"
export NIRI_SOCKET="${NIRI_SOCKET:-$(ls "${XDG_RUNTIME_DIR}"/niri.*.sock 2>/dev/null | head -1)}"

layer_count() {
  [ -n "$NIRI_SOCKET" ] || { echo 0; return; }
  timeout 3 niri msg layers 2>/dev/null | grep -c "Namespace" || echo 0
}

log() { echo "[noctalia-start] $* $(date -Is)" >> "$LOG"; }

while true; do
  # Re-resolve the niri socket in case niri restarted.
  export NIRI_SOCKET="$(ls "${XDG_RUNTIME_DIR}"/niri.*.sock 2>/dev/null | head -1)"

  if pgrep -x quickshell >/dev/null 2>&1; then
    if [ "$(layer_count)" -ge 1 ]; then
      sleep 5; continue          # healthy: bar/dock/wallpaper mapped
    fi
    log "quickshell running but no layers mapped; restarting"
    pkill -x quickshell; sleep 1
  fi

  rm -rf "${XDG_RUNTIME_DIR}/quickshell/by-path" 2>/dev/null
  log "starting noctalia-shell"
  noctalia-shell >> "$LOG" 2>&1 &
  NPID=$!

  # Give it up to 20s to map a layer surface; otherwise assume it froze.
  ok=0
  for _ in $(seq 1 20); do
    sleep 1
    kill -0 "$NPID" 2>/dev/null || break
    if [ "$(layer_count)" -ge 1 ]; then ok=1; break; fi
  done
  if [ "$ok" = 1 ]; then
    log "noctalia mapped its shell; supervising"
    wait "$NPID"
    log "noctalia exited ($?); will relaunch"
  else
    log "noctalia did not map a shell in time (no client streaming yet?); retrying"
    kill "$NPID" 2>/dev/null; pkill -x quickshell 2>/dev/null
  fi
  sleep 3
done
