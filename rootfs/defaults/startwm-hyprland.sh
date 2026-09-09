#!/bin/bash
# Hyprland nested inside pixelflux's compositor (parent is WAYLAND_DISPLAY=wayland-1).
# Aquamarine selects its Wayland backend automatically when WAYLAND_DISPLAY is set.
ulimit -c 0
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
# Same reason as the niri image: a nested compositor blocks in eglSwapBuffers
# waiting on the parent's frame callback, and pixelflux only renders while a
# browser is attached. Swap interval 0 stops Hyprland stalling before anyone
# has connected.
export vblank_mode=0
export WLR_RENDERER_ALLOW_SOFTWARE=1
exec Hyprland
