#!/bin/bash
# webtop:arch-i3 equivalent. i3 finds its stock config in the Nix store.
ulimit -c 0
# Enable Nvidia GPU support if detected (mirrors linuxserver's startwm.sh)
if command -v nvidia-smi >/dev/null 2>&1 && ls -A /dev/dri >/dev/null 2>&1 && [ "${DISABLE_ZINK}" = "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi
exec i3
