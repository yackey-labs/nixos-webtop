#!/bin/bash
# scoot headless, captured by wayvnc and served to browsers by noVNC.
#
# No pixelflux, no nested host: scoot IS the compositor here, running
# --headless directly with --width/--height as the authoritative output size
# (there is no host to negotiate with, so unlike --nested nothing can reflow
# it later -- see the fixed-size note below).
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
# deliberately drops, and any X client can keylog by design. Everything in
# this image is Wayland-native, so there is nothing to gain.
export GDK_BACKEND=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
# Deliberately NOT set: vblank_mode=0. scoot renders with pixman into wl_shm
# buffers on its own 16 ms timer and its present() drops a frame rather than
# blocking, so there is nothing to stall on -- with no parent compositor at
# all here, even less than in the nested image.

# ── The look ─────────────────────────────────────────────────────────────
# Same four looks as the Selkies image, from the one shared seeding script
# (scoot-look-seed.sh): same files, same backup convention, same marker, same
# Alt+Super doubled binds (a browser tab rarely sees Super, so the Alt column
# is what works on first open -- see the look files).
# shellcheck source=/dev/null
. /defaults/scoot-look-seed.sh

# ── Remote input ─────────────────────────────────────────────────────────
# wayvnc drives the session through zwlr_virtual_pointer_manager_v1 (v2) and
# zwp_virtual_keyboard_manager_v1, which scoot only advertises with
# [virtual_input] enabled = true (restart-only; off means unadvertised).
# The look files deliberately do NOT carry it -- they are shared with the
# Selkies image, whose session must never offer remote-control globals --
# so it is ensured here, every start, on the seeded config only:
ensure_virtual_input() { # config path; idempotent, backs up before changing
  cfg="$1"
  [ -f "$cfg" ] || return 0
  if grep -q '^\[virtual_input\]' "$cfg"; then
    if grep -q '^enabled *= *true' "$cfg"; then
      return 0
    fi
    ts=$(date +%s%N); suffix="$ts"; i=0
    while [ -e "$cfg.bak-$suffix" ]; do i=$((i+1)); suffix="${ts}-$i"; done
    cp -p "$cfg" "$cfg.bak-$suffix" || return 1
    # Flip enabled inside the existing [virtual_input] section only: from
    # its header to the next section header.
    awk 'BEGIN{invi=0} /^\[virtual_input\]/{invi=1; print; next} /^\[/{invi=0} invi && /^[[:space:]]*enabled[[:space:]]*=/{print "enabled = true"; next} {print}' \
      "$cfg" > "$cfg.new" || return 1
    # The section may name no enabled key at all; then the awk above changed
    # nothing, so append it under the header instead.
    if ! awk '/^\[virtual_input\]/{invi=1; next} /^\[/{invi=0} invi && /^[[:space:]]*enabled[[:space:]]*=/{found=1} END{exit !found}' "$cfg.new"; then
      awk '/^\[virtual_input\]/{print; print "enabled = true"; next} {print}' \
        "$cfg.new" > "$cfg.new2" && mv "$cfg.new2" "$cfg.new" || return 1
    fi
    mv "$cfg.new" "$cfg" || return 1
    echo "[startwm-scoot-vnc] enabled [virtual_input] in $cfg (backup $cfg.bak-$suffix)" >&2
  else
    ts=$(date +%s%N); suffix="$ts"; i=0
    while [ -e "$cfg.bak-$suffix" ]; do i=$((i+1)); suffix="${ts}-$i"; done
    cp -p "$cfg" "$cfg.bak-$suffix" || return 1
    printf '\n[virtual_input]\nenabled = true\n' >> "$cfg" || return 1
    echo "[startwm-scoot-vnc] appended [virtual_input] enabled = true to $cfg" >&2
  fi
}
ensure_virtual_input "$HOME/.config/scoot/config.toml" || {
  echo "[startwm-scoot-vnc] ERROR: could not ensure [virtual_input]; remote input will not work" >&2
}

# Every start, not just seeding ones: a restarted container keeps its seeded
# files but gets a fresh environment, and scoot inherits this one -- so the
# bar's exec modules resolve load.sh/cpu.sh through it either way.
export PATH="$HOME/.config/scoot/bin:$PATH"

# The output size. --headless has no host, so --width/--height are
# authoritative for the life of the session: noVNC's resize can NOT drive
# them (ExtendedDesktopSize has no path to a headless output's size -- there
# is no output-management protocol for wayvnc to speak, and scoot sizes
# headless outputs from these flags alone). The browser scales the fixed
# framebuffer to its window locally instead. VNC_WIDTH/VNC_HEIGHT override;
# SELKIES_MANUAL_WIDTH/HEIGHT are honored as aliases so the benchmark runs
# both images at the same size with one knob.
W="${VNC_WIDTH:-${SELKIES_MANUAL_WIDTH:-1280}}"; H="${VNC_HEIGHT:-${SELKIES_MANUAL_HEIGHT:-800}}"
[ "$W" = "0" ] && W=1280
[ "$H" = "0" ] && H=800
N="${VNC_OUTPUTS:-1}"
case "$N" in
  ''|*[!0-9]*) echo "[startwm-scoot-vnc] bad VNC_OUTPUTS='$N', using 1" >&2; N=1 ;;
esac
[ "$N" -ge 1 ] && [ "$N" -le 8 ] || { echo "[startwm-scoot-vnc] VNC_OUTPUTS='$N' out of 1-8, using 1" >&2; N=1; }

exec scoot --headless --width "$W" --height "$H" --outputs "$N" -- /defaults/scoot-session-vnc.sh
