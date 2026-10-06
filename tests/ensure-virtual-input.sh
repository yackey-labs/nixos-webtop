#!/usr/bin/env bash
# Fixture tests for ensure_virtual_input (rootfs/defaults/ensure-virtual-input.sh).
#
# Run:  bash tests/ensure-virtual-input.sh
# Also wired into `nix flake check` (checks.ensure-virtual-input) and CI's
# `test` job, so no fix here can rot silently.
#
# Each case builds a fixture config file, runs the REAL function sourced
# from the repo file, and byte-compares the result (cmp) plus asserts
# whether a backup was taken (no spurious backups when nothing changes).
set -u
FUNC_FILE="${1:-$(dirname "$0")/../rootfs/defaults/ensure-virtual-input.sh}"
# shellcheck source=/dev/null
. "$FUNC_FILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0
fail=0

# run_case name cfg want want_backup [env]
# cfg/want are file paths; want_backup is yes/no; env is the value for
# VNC_VIRTUAL_INPUT (unset when absent).
run_case() {
  local name="$1" cfg="$2" want="$3" want_backup="$4" extra_env="${5:-__unset__}"
  rm -f "$cfg".bak-*
  local err="$WORK/$name.stderr"
  local rc=0
  if [ "$extra_env" = "__unset__" ]; then
    unset VNC_VIRTUAL_INPUT
    ensure_virtual_input "$cfg" 2>"$err" || rc=1
  else
    VNC_VIRTUAL_INPUT="$extra_env" ensure_virtual_input "$cfg" 2>"$err" || rc=1
  fi
  if [ "$rc" != "0" ]; then
    echo "FAIL $name: function exited nonzero"; fail=$((fail+1)); return
  fi
  if ! cmp -s "$cfg" "$want"; then
    echo "FAIL $name: content mismatch (diff cfg vs want)"
    diff "$cfg" "$want" || true
    fail=$((fail+1)); return
  fi
  local backups
  backups="$(ls "$cfg".bak-* 2>/dev/null | wc -l | tr -d ' ')"
  local want_n=0
  [ "$want_backup" = "yes" ] && want_n=1
  if [ "$backups" != "$want_n" ]; then
    echo "FAIL $name: backups=$backups, want $want_n"
    fail=$((fail+1)); return
  fi
  echo "PASS $name"
  pass=$((pass+1))
}

mk() { # path, then stdin -> file
  local f="$1"; cat > "$f"
}

# 1. append: no section at all -> table appended, backup taken
mk "$WORK/append.toml" <<'EOF'
[other]
enabled = false
EOF
mk "$WORK/append.want" <<'EOF'
[other]
enabled = false

[virtual_input]
enabled = true
EOF
run_case "append" "$WORK/append.toml" "$WORK/append.want" yes

# 2. flip: false -> true inside the section, other sections untouched
mk "$WORK/flip.toml" <<'EOF'
[virtual_input]
enabled = false
[other]
foo = 1
EOF
mk "$WORK/flip.want" <<'EOF'
[virtual_input]
enabled = true
[other]
foo = 1
EOF
run_case "flip" "$WORK/flip.toml" "$WORK/flip.want" yes

# 3. already-true: untouched, NO backup
mk "$WORK/true.toml" <<'EOF'
[virtual_input]
enabled = true
EOF
run_case "already-true" "$WORK/true.toml" "$WORK/true.toml" no

# 3b. already-true, tight spacing and indented: untouched, NO backup
mk "$WORK/truetight.toml" <<'EOF'
[virtual_input]
  enabled=true
EOF
run_case "already-true-tight-indented" "$WORK/truetight.toml" "$WORK/truetight.toml" no

# 3c. already-true with trailing comment: untouched, NO backup
mk "$WORK/truecomment.toml" <<'EOF'
[virtual_input]
enabled = true # keep
EOF
run_case "already-true-comment" "$WORK/truecomment.toml" "$WORK/truecomment.toml" no

# 4. B3 case: another section's `enabled = true` must NOT satisfy the check --
# [virtual_input] is false, so it must still be flipped (old code no-op'd).
mk "$WORK/b3.toml" <<'EOF'
[xwayland]
enabled = true
[virtual_input]
enabled = false
EOF
mk "$WORK/b3.want" <<'EOF'
[xwayland]
enabled = true
[virtual_input]
enabled = true
EOF
run_case "other-sections-true" "$WORK/b3.toml" "$WORK/b3.want" yes

# 4b. only another section is true and there is NO [virtual_input] section:
# exactly one table appended (never zero, never two).
mk "$WORK/nosec.toml" <<'EOF'
[xwayland]
enabled = true
EOF
mk "$WORK/nosec.want" <<'EOF'
[xwayland]
enabled = true

[virtual_input]
enabled = true
EOF
run_case "other-true-no-section" "$WORK/nosec.toml" "$WORK/nosec.want" yes

# 5. header with trailing whitespace is the same section: flipped in place,
# never a duplicate table (the header line itself is left verbatim).
printf '[virtual_input]   \nenabled = false\n' > "$WORK/space.toml"
printf '[virtual_input]   \nenabled = true\n' > "$WORK/space.want"
run_case "header-trailing-space" "$WORK/space.toml" "$WORK/space.want" yes

# 5b. space inside the brackets is the same section too (valid TOML):
# flipped in place, never a duplicate table.
printf '[virtual_input ]\nenabled = false\n' > "$WORK/inbracket.toml"
printf '[virtual_input ]\nenabled = true\n' > "$WORK/inbracket.want"
run_case "header-space-in-brackets" "$WORK/inbracket.toml" "$WORK/inbracket.want" yes

# 5c. an indented later header ends [virtual_input] too: its `enabled = true`
# must not satisfy the check (the B3 class again, round-2 review N2), and the
# key is inserted under [virtual_input], not flipped in [other].
printf '[virtual_input]\nfoo = 1\n  [other]\nenabled = true\n' > "$WORK/indhdr.toml"
printf '[virtual_input]\nenabled = true\nfoo = 1\n  [other]\nenabled = true\n' > "$WORK/indhdr.want"
run_case "indented-later-header" "$WORK/indhdr.toml" "$WORK/indhdr.want" yes
mk "$WORK/hcomment.toml" <<'EOF'
[virtual_input] # remote input
foo = 1
EOF
mk "$WORK/hcomment.want" <<'EOF'
[virtual_input] # remote input
enabled = true
foo = 1
EOF
run_case "header-trailing-comment" "$WORK/hcomment.toml" "$WORK/hcomment.want" yes

# 6. no final newline: still flipped, output newline-terminated.
printf '[virtual_input]\nenabled=false' > "$WORK/nonl.toml"
mk "$WORK/nonl.want" <<'EOF'
[virtual_input]
enabled = true
EOF
run_case "no-final-newline" "$WORK/nonl.toml" "$WORK/nonl.want" yes

# 7. a comment line naming the key is NOT the key: the real key is added,
# the comment left alone.
mk "$WORK/comment.toml" <<'EOF'
[virtual_input]
# enabled = true
foo = 1
EOF
mk "$WORK/comment.want" <<'EOF'
[virtual_input]
enabled = true
# enabled = true
foo = 1
EOF
run_case "comment-line" "$WORK/comment.toml" "$WORK/comment.want" yes

# 8. opt-out: VNC_VIRTUAL_INPUT=0 leaves a false config alone, no backup,
# and says loudly on stderr that input is off.
mk "$WORK/optout.toml" <<'EOF'
[virtual_input]
enabled = false
EOF
run_case "opt-out" "$WORK/optout.toml" "$WORK/optout.toml" no 0
if grep -q "REMOTE INPUT OFF" "$WORK/opt-out.stderr"; then
  echo "PASS opt-out-loud"; pass=$((pass+1))
else
  echo "FAIL opt-out-loud: no loud log on stderr"; fail=$((fail+1))
fi

# 9. idempotency: a second run changes nothing and takes no second backup.
mk "$WORK/idem.toml" <<'EOF'
[comp]
foo = 1
EOF
unset VNC_VIRTUAL_INPUT
ensure_virtual_input "$WORK/idem.toml" 2>/dev/null
ensure_virtual_input "$WORK/idem.toml" 2>/dev/null
if [ "$(ls "$WORK/idem.toml".bak-* 2>/dev/null | wc -l | tr -d ' ')" = "1" ] \
  && [ "$(grep -c 'virtual_input' "$WORK/idem.toml")" = "1" ]; then
  echo "PASS idempotent"; pass=$((pass+1))
else
  echo "FAIL idempotent"; fail=$((fail+1))
fi

echo "--- $pass passed, $fail failed ---"
[ "$fail" = "0" ]
