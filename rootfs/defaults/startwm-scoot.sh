#!/bin/bash
# scoot nested inside pixelflux's compositor (parent is WAYLAND_DISPLAY=wayland-1).
#
# scoot has no backend auto-detection: --headless, --nested and --tty are
# explicit, so the nesting is spelled out here rather than inferred from
# WAYLAND_DISPLAY the way niri's winit backend and Hyprland's aquamarine do.
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
# deliberately drops (x11 = false), and any X client can keylog by design.
# Everything in this image is Wayland-native, so there is nothing to gain.
export GDK_BACKEND=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
# Deliberately NOT set: vblank_mode=0. The niri and Hyprland images need it
# because their nested backends block in eglSwapBuffers until the parent
# sends a frame callback, and pixelflux only renders while a browser is
# attached. scoot renders with pixman into wl_shm buffers on its own 16 ms
# timer and its present() drops a frame rather than blocking when the host
# has released neither buffer, so there is nothing to stall on.

# ── The look ─────────────────────────────────────────────────────────────
# SCOOT_LOOK picks one of the looks in /defaults/scoot-looks (scoot's example
# looks, adapted for this image; see NOTICE.scoot-looks beside them).
# radial-burst is the default: dark and high-contrast, which survives
# x264 + CSS scaling to a phone screen best; music-desk's paper white costs
# more encoded pixels and washes out faster, and vinyl-sunset ships without
# its illustration for licensing reasons. One image, not four: the looks
# are kilobytes of config plus three small PNGs, so splitting would quadruple
# the registry entries for no measured gain.
LOOK="${SCOOT_LOOK:-radial-burst}"
case "$LOOK" in
  radial-burst|music-desk|vinyl-sunset|moonrise) ;;
  *) echo "[startwm-scoot] unknown SCOOT_LOOK='$LOOK', falling back to radial-burst" >&2
     LOOK=radial-burst ;;
esac
export SCOOT_LOOK="$LOOK"
SRC="/defaults/scoot-looks/$LOOK"

# Seed the look's files into the user's config on first use, or when the look
# changes. A file the user edited is kept as <file>.bak-<timestamp>, never
# silently overwritten; switching back and forth between looks re-seeds each
# time (with a backup when the file differs), so a look switch never merges.
#
# Seeded files are user-writable: the /defaults originals are nix-store
# read-only (mode 444), so a plain `cp` would seed a 444 copy that a later
# look switch cannot overwrite in place (GNU cp opens the existing inode) --
# the switch would fail with Permission denied while the marker still flipped,
# silently keeping the old look. `--remove-destination` unlinks first and
# `chmod u+w` after guarantees writability either way.
seed() { # src dest; returns nonzero on failure
  mkdir -p "$(dirname "$2")" || return 1
  # sha256sum, not cmp: diffutils is not in this image, so cmp is missing
  # (it would fail every comparison and back up even identical files).
  # The cut keeps the hash only: sha256sum prints "<hash>  <path>", and the
  # paths always differ.
  if [ -f "$2" ] && [ "$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)" != "$(sha256sum "$2" 2>/dev/null | cut -d' ' -f1)" ]; then
    # Nanosecond timestamp plus a collision loop: two switches inside one
    # second (or one nanosecond, or a date without %N) must not overwrite
    # the first backup.
    ts=$(date +%s%N)
    suffix="$ts"
    i=0
    while [ -e "$2.bak-$suffix" ]; do
      i=$((i+1))
      suffix="${ts}-$i"
    done
    cp -p "$2" "$2.bak-$suffix" || return 1
  fi
  cp --remove-destination "$1" "$2" || return 1
  chmod u+w "$2" || return 1
}
MARKER="$HOME/.config/.scoot-look"
if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$LOOK" ]; then
  echo "[startwm-scoot] seeding look '$LOOK' into $HOME/.config" >&2
  seed_ok=1
  seed "$SRC/scoot.toml" "$HOME/.config/scoot/config.toml" || seed_ok=0
  seed "$SRC/bar.toml" "$HOME/.config/scoot/bar.toml" || seed_ok=0
  seed "$SRC/foot.ini" "$HOME/.config/foot/foot.ini" || seed_ok=0
  [ -f "$SRC/starship.toml" ] && { seed "$SRC/starship.toml" "$HOME/.config/starship.toml" || seed_ok=0; }
  if [ -d "$SRC/helix" ]; then
    while IFS= read -r rel; do
      rel="${rel#./}"
      seed "$SRC/helix/$rel" "$HOME/.config/helix/$rel" || seed_ok=0
    done < <(cd "$SRC/helix" && find . -type f)
  fi
  if [ -d "$SRC/btop" ]; then
    while IFS= read -r rel; do
      rel="${rel#./}"
      seed "$SRC/btop/$rel" "$HOME/.config/btop/$rel" || seed_ok=0
    done < <(cd "$SRC/btop" && find . -type f)
  fi
  [ -f "$SRC/lazygit.yml" ] && { seed "$SRC/lazygit.yml" "$HOME/.config/lazygit/config.yml" || seed_ok=0; }
  # The bar's command modules (bar.toml's [exec.load]/[exec.cpu] run these by
  # bare name). They live beside the configs that reference them, not in
  # ~/.local/bin: Selkies (running as root) owns ~/.local/state, so ~/.local
  # itself is root-owned and this user cannot create ~/.local/bin there.
  for helper in load.sh cpu.sh; do
    if seed "/defaults/scoot-bin/$helper" "$HOME/.config/scoot/bin/$helper"; then
      chmod +x "$HOME/.config/scoot/bin/$helper" || seed_ok=0
    else
      seed_ok=0
    fi
  done
  # The prompt: starship reads ~/.config/starship.toml by default, so this
  # only wires the init line in once. Looks without a starship.toml (radial
  # burst) leave whatever the shell had.
  if [ -f "$SRC/starship.toml" ]; then
    if [ ! -f "$HOME/.bashrc" ]; then
      printf '# Seeded by startwm-scoot.sh for the scoot looks.\ncommand -v starship >/dev/null && eval "$(starship init bash)"\n' > "$HOME/.bashrc"
    elif ! grep -q 'starship init bash' "$HOME/.bashrc"; then
      printf 'command -v starship >/dev/null && eval "$(starship init bash)"\n' >> "$HOME/.bashrc"
    fi
  fi
  # The marker flips only when every file landed: a failed switch keeps
  # the old marker, so the next start retries the seed instead of running
  # the new look's session on the old look's files.
  if [ "$seed_ok" -eq 1 ]; then
    echo "$LOOK" > "$MARKER"
  else
    echo "[startwm-scoot] ERROR: seeding look '$LOOK' failed; keeping old marker" >&2
  fi
fi

# Every start, not just seeding ones: a restarted container keeps its seeded
# files but gets a fresh environment, and scoot inherits this one -- so the
# bar's exec modules resolve load.sh/cpu.sh through it either way.
export PATH="$HOME/.config/scoot/bin:$PATH"

# The size to come up at. scoot follows the host's size for the life of the
# session now (scoot-sh/scoot#144, fixed upstream), so a later browser resize
# reflows rather than letterboxing, and this is only the starting point --
# what the desktop looks like before anyone has connected, and what it falls
# back to if pixelflux answers the first configure with 0x0 ("you choose").
W="${SELKIES_MANUAL_WIDTH:-1280}"; H="${SELKIES_MANUAL_HEIGHT:-800}"
[ "$W" = "0" ] && W=1280
[ "$H" = "0" ] && H=800

exec scoot --nested --width "$W" --height "$H" -- /defaults/scoot-session.sh
