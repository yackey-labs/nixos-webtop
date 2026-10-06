# ensure_virtual_input: make sure scoot advertises the virtual-pointer and
# virtual-keyboard globals wayvnc drives the session through.
#
# wayvnc captures video regardless, but without `[virtual_input]
# enabled = true` (restart-only; off means unadvertised) no input ever
# reaches the session -- silently. The look files deliberately do NOT carry
# the key (they are shared with the Selkies image, whose session must never
# offer remote-control globals), so this runs on the seeded config every
# start, idempotently, backing up before any change.
#
# Opt-out: VNC_VIRTUAL_INPUT=0 skips the whole thing (and says so loudly):
# for a deliberately input-less, view-only desktop.
ensure_virtual_input() { # config path; idempotent, backs up before changing
  if [ "${VNC_VIRTUAL_INPUT:-}" = "0" ]; then
    echo "[startwm-scoot-vnc] VNC_VIRTUAL_INPUT=0: leaving [virtual_input] alone -- REMOTE INPUT OFF (video only, no pointer or keyboard)" >&2
    return 0
  fi
  cfg="$1"
  [ -f "$cfg" ] || return 0
  # Section header match, shared by the check and the flip below: the
  # section name with optional surrounding whitespace and an optional
  # trailing comment. A different section header ends the section.
  if awk '/^[[:space:]]*\[[[:space:]]*virtual_input[[:space:]]*][[:space:]]*(#.*)?$/{invi=1; next} /^\[/{invi=0; next} invi && /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$/{found=1} END{exit !found}' "$cfg"; then
    return 0
  fi
  ts=$(date +%s%N); suffix="$ts"; i=0
  while [ -e "$cfg.bak-$suffix" ]; do i=$((i+1)); suffix="${ts}-$i"; done
  cp -p "$cfg" "$cfg.bak-$suffix" || return 1
  if awk '/^[[:space:]]*\[[[:space:]]*virtual_input[[:space:]]*][[:space:]]*(#.*)?$/{found=1} END{exit !found}' "$cfg"; then
    # Flip enabled inside the existing [virtual_input] section(s) only:
    # from their headers to the next section headers. Never touches an
    # `enabled` key in any other section, and never appends a table.
    awk 'BEGIN{invi=0} /^[[:space:]]*\[[[:space:]]*virtual_input[[:space:]]*][[:space:]]*(#.*)?$/{invi=1; print; next} /^[[:space:]]*\[/{invi=0} invi && /^[[:space:]]*enabled[[:space:]]*=/{print "enabled = true"; next} {print}' \
      "$cfg" > "$cfg.new" || return 1
    # The section may name no enabled key at all; then the awk above changed
    # nothing, so insert the key under the first header instead.
    if ! awk '/^[[:space:]]*\[[[:space:]]*virtual_input[[:space:]]*][[:space:]]*(#.*)?$/{invi=1; next} /^\[/{invi=0; next} invi && /^[[:space:]]*enabled[[:space:]]*=/{found=1} END{exit !found}' "$cfg.new"; then
      awk '/^[[:space:]]*\[[[:space:]]*virtual_input[[:space:]]*][[:space:]]*(#.*)?$/ && !done{print; print "enabled = true"; done=1; next} {print}' \
        "$cfg.new" > "$cfg.new2" && mv "$cfg.new2" "$cfg.new" || return 1
    fi
    mv "$cfg.new" "$cfg" || return 1
    echo "[startwm-scoot-vnc] enabled [virtual_input] in $cfg (backup $cfg.bak-$suffix)" >&2
  else
    printf '\n[virtual_input]\nenabled = true\n' >> "$cfg" || return 1
    echo "[startwm-scoot-vnc] appended [virtual_input] enabled = true to $cfg" >&2
  fi
}
