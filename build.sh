#!/usr/bin/env bash
# Build an image with Nix and load it into the local Docker daemon.
# Works on macOS (no Nix needed): builds inside a nixos/nix container that
# matches the host's CPU architecture, then streams the tarball into `docker load`.
#
#   ./build.sh                    # builds .#image-webtop-i3
#   ./build.sh image-base         # builds .#image-base
#   ./build.sh image-webtop-i3 x86_64-linux   # cross/emulated build (slow on Apple Silicon)
set -euo pipefail

TARGET="${1:-image-webtop-i3}"
case "${2:-$(uname -m)}" in
  arm64|aarch64|aarch64-linux) SYSTEM=aarch64-linux; PLATFORM=linux/arm64 ;;
  x86_64|amd64|x86_64-linux)   SYSTEM=x86_64-linux;  PLATFORM=linux/amd64 ;;
  *) echo "unknown arch: $2" >&2; exit 1 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
VOLUME="nixwebtop-store-${SYSTEM}"
CONTAINER="nixwebtop-builder-${SYSTEM}"

if command -v nix >/dev/null 2>&1 && [ "$(uname -s)" = "Linux" ]; then
  out="$(nix build "$HERE#packages.${SYSTEM}.${TARGET}" --no-link --print-out-paths)"
  docker load < "$out"
  exit 0
fi

if ! docker ps -q -f "name=^${CONTAINER}$" | grep -q .; then
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --platform "$PLATFORM" --name "$CONTAINER" \
    -v "${VOLUME}:/nix" -v "$HERE:/work" -w /work \
    nixos/nix:latest sleep infinity >/dev/null
  docker exec "$CONTAINER" sh -c 'mkdir -p /etc/nix && printf "experimental-features = nix-command flakes\nmax-jobs = auto\nsandbox = false\nfilter-syscalls = false\n" > /etc/nix/nix.conf'
fi

echo ">> building .#packages.${SYSTEM}.${TARGET} in ${CONTAINER}"
out="$(docker exec "$CONTAINER" nix build "/work#packages.${SYSTEM}.${TARGET}" --no-link --print-out-paths -L)"
echo ">> loading ${out} into docker"
docker exec "$CONTAINER" cat "$out" | docker load
