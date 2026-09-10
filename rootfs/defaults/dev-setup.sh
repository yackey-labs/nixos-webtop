#!/usr/bin/env bash
# One-shot developer setup. Everything it installs lands in $HOME (/config),
# which is the PVC — so it survives image rebuilds and updates itself without
# one. Safe to re-run; it is idempotent.
set -euo pipefail
mkdir -p "$HOME/.local/bin"

echo "==> mise: language runtimes"
if command -v mise >/dev/null 2>&1; then
  # Native builds by default. Add or change versions freely afterwards with
  # `mise use -g <lang>@<version>`; nothing here needs the image rebuilt.
  mise settings set idiomatic_version_file_enable_tools "[]" 2>/dev/null || true
  for tool in "${@:-node@lts python@3.13 go@latest rust@stable}"; do
    echo "    mise use -g $tool"
    mise use -g "$tool" || echo "    (failed: $tool — continuing)"
  done
  mise reshim 2>/dev/null || true
else
  echo "    mise not on PATH; skipping"
fi

echo "==> Claude Code"
if command -v claude >/dev/null 2>&1; then
  echo "    already installed: $(claude --version 2>/dev/null || echo present)"
  claude update 2>/dev/null || true
else
  # Native installer, into ~/.local/bin. Self-updates from then on.
  curl -fsSL https://claude.ai/install.sh | bash || {
    echo "    native installer failed; falling back to npm"
    npm install -g @anthropic-ai/claude-code --prefix "$HOME/.local" || true
  }
fi

echo
echo "Done. Installed under \$HOME (/config), which is persistent:"
echo "  mise   -> \$HOME/.local/share/mise   (mise use -g <lang>@<ver>)"
echo "  claude -> \$HOME/.local/bin/claude   (claude update)"
echo "Neither needs the container image rebuilt to change or update."
