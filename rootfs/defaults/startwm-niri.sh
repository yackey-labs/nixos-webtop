#!/bin/bash
# niri nested inside pixelflux's compositor (WAYLAND_DISPLAY=wayland-1 is the parent).
# niri picks its winit backend automatically when WAYLAND_DISPLAY is set.
ulimit -c 0
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XDG_CURRENT_DESKTOP=niri
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
# niri's nested (winit) backend blocks in eglSwapBuffers until the parent
# compositor sends a frame callback, and pixelflux only renders while a browser
# is attached. vblank_mode=0 makes Mesa use swap interval 0 so niri never blocks.
export vblank_mode=0
exec niri
