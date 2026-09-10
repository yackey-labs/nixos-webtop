# nixos-webtop

A Nix flake that builds Docker images equivalent to
[linuxserver/docker-baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies)
and [linuxserver/docker-webtop `arch-i3`](https://github.com/linuxserver/docker-webtop/blob/arch-i3/Dockerfile),
with every binary coming from nixpkgs instead of pacman/apt.

Open `http://localhost:3000` and you get a full Linux desktop (i3 + xfce4-terminal + Chromium)
streamed by [Selkies](https://github.com/selkies-project/selkies) over WebSockets.

![i3 desktop streamed from the aarch64 image](docs-screenshot.png)

![niri + noctalia-shell streamed from the aarch64 image](docs-screenshot-niri.png)

## License

GPL-3.0. This is a port of [linuxserver/docker-baseimage-selkies][lsb] and
[linuxserver/docker-webtop][lsw], both GPL-3.0, so the same terms apply here.
[Selkies][sel] itself is MPL-2.0 and is consumed unmodified from upstream.

[lsb]: https://github.com/linuxserver/docker-baseimage-selkies
[lsw]: https://github.com/linuxserver/docker-webtop
[sel]: https://github.com/selkies-project/selkies

## Images

| flake output       | what it is                                                | linuxserver equivalent          |
|--------------------|-----------------------------------------------------------|---------------------------------|
| `image-base`       | Xvfb + openbox + st/xterm + Selkies + nginx + PulseAudio  | `baseimage-selkies`             |
| `image-webtop-i3`  | `image-base` + i3, i3status, dmenu, xfce4-terminal, Chromium | `webtop:arch-i3`             |
| `image-webtop-niri`| Wayland mode: niri + noctalia-shell, foot, Chromium (Wayland), nautilus, xwayland-satellite | no direct equivalent (closest: `webtop:arch-i3` with `PIXELFLUX_WAYLAND=true`/sway) |
| `image-webtop-hyprland`| Wayland mode: Hyprland + waybar, fuzzel, mako, swaybg, foot, Chromium | no equivalent |

Both are `dockerTools.buildLayeredImage` outputs for `x86_64-linux` and `aarch64-linux`.

## Build and run

You do not need Nix installed. `build.sh` runs the build in a `nixos/nix` container
matching your CPU and loads the result into Docker:

```sh
./build.sh                  # -> selkies-nix-webtop-i3:latest
./build.sh image-webtop-niri # -> selkies-nix-webtop-niri:latest
./build.sh image-base       # -> selkies-nix-base:latest

docker run -d --name webtop \
  -p 3000:3000 -p 3001:3001 \
  --shm-size=1g \
  -v webtop-config:/config \
  -e PUID=1000 -e PGID=1000 -e TITLE="Nix i3" \
  selkies-nix-webtop-i3:latest
```

With Nix on Linux: `nix build .#image-webtop-i3 && docker load < result`.

Ports: `3000` HTTP, `3001` HTTPS with a self-signed cert generated into `/config/ssl`.

## Environment variables

The runtime honours the same knobs as the linuxserver image where they make sense:

`PUID`, `PGID`, `TITLE`, `PASSWORD` (basic auth), `CUSTOM_USER`, `CUSTOM_PORT`, `CUSTOM_HTTPS_PORT`,
`CUSTOM_WS_PORT`, `SUBFOLDER`, `DASHBOARD` (`selkies-dashboard` or `selkies-dashboard-wish`),
`FILE_MANAGER_PATH`, `SELKIES_FILE_TRANSFERS`, `DISABLE_IPV6`, `SELKIES_MANUAL_WIDTH/HEIGHT`, `MAX_RES`,
`HARDEN_DESKTOP`, `DISABLE_SUDO`, `NO_GAMEPAD`, `LC_ALL`, plus any `SELKIES_*` setting
Selkies itself reads. Set `SKIP_CHOWN_CONFIG=true` to skip the recursive chown of `/config`.

Drop an executable `startwm.sh` in `/config/.config/` to replace the window manager launcher.

## How it maps to the linuxserver image

| linuxserver                          | here                                                        |
|--------------------------------------|-------------------------------------------------------------|
| s6-overlay `init-*` oneshots         | `rootfs/init` (bash, then `exec s6-svscan`)                  |
| s6-overlay `svc-*` longruns          | `rootfs/etc/s6/service/*/run`, supervised by `s6-svscan`     |
| `/defaults/*`                        | `rootfs/defaults/*` (nginx template, PulseAudio, dbus, WM)   |
| `pip install .` of selkies           | `nix/selkies.nix` (`buildPythonApplication`)                 |
| pixelflux/pcmflux from PyPI          | `nix/pixelflux.nix`, `nix/pcmflux.nix` (manylinux wheels + autoPatchelf) |
| npm builds of web-core + dashboards  | `nix/selkies-web.nix` (`buildNpmPackage`, lockfiles in `frontend/locks`) |
| js-interposer + fake-udev            | `nix/selkies-addons.nix`                                     |
| nginx + `nginx-mod-fancyindex` (AUR) | `nix/nginx.nix` (`nginxModules.fancyindex`)                  |
| `/usr/bin/chromium` wrapper          | `hiPrio writeShellScriptBin "chromium"` in `flake.nix`       |
| patched Xvfb (`-vfbdevice` DRI3)     | stock Xvfb from nixpkgs, software rendering only            |

Filesystem layout inside the container: `/usr/{bin,lib,share,etc}` are symlinks into a
`buildEnv` of all packages, so `PATH=/usr/bin` behaves like a normal distro. `/etc` holds
real files (passwd, group, sudoers, pam.d, fonts.conf) so `usermod`/`groupmod` can edit them
at start for `PUID`/`PGID`. `sudo` is copied to `/usr/local/bin` and made setuid in
`fakeRootCommands`.

## Adding your own webtop flavour

In `flake.nix`, call `mkSelkiesImage` with a different `startwm` script and package list:

```nix
image-webtop-xfce = self.mkSelkiesImage {
  name = "selkies-nix-webtop-xfce";
  title = "Nix XFCE";
  startwm = ./rootfs/defaults/startwm-xfce.sh;   # exec startxfce4
  extraPackages = with final; [ xfce.xfce4-session xfce.xfce4-panel xfce.xfdesktop xfce.thunar firefox ];
};
```

## Updating pins

- Selkies commit and hashes: `selkiesSrc` in `flake.nix`, `nix/python-xlib-selkies.nix`.
- pixelflux/pcmflux wheels: the tables in `nix/pixelflux.nix` and `nix/pcmflux.nix`
  (add a row for the Python version nixpkgs ships; hashes from `pip download` or PyPI).
- Frontend: regenerate `frontend/locks/*.package-lock.json` with
  `npm install --package-lock-only` in each `addons/*` directory, then
  `nix run nixpkgs#prefetch-npm-deps -- <lockfile>` for the new `npmDepsHash`.

## Wayland mode (niri image)

`mkSelkiesImage { wayland = true; ... }` sets `PIXELFLUX_WAYLAND=true`. Selkies then starts
pixelflux's built-in Smithay compositor on `wayland-1` instead of Xvfb being captured, and the
`de` service waits for that socket and runs `startwm.sh` with `WAYLAND_DISPLAY=wayland-1`.
niri detects the parent compositor and runs nested via its winit backend; noctalia-shell is
started from niri's config (`spawn-at-startup`). The seeded config lives in
`rootfs/config/niri/config.kdl` and is copied to `/config/.config/niri/` on first run only.

Keys: `Mod+T` foot, `Mod+D` noctalia launcher, `Mod+B` Chromium, `Mod+E` nautilus,
`Mod+Shift+/` hotkey overlay. `Mod` is Super in niri; in a browser that usually needs the
Selkies sidebar's keyboard-lock toggle or remapping to avoid the host grabbing the key.

## Not ported (yet)

- linuxserver's labwc-based Wayland desktop (patched labwc/wlroots, selkies-desktop).
- Docker-in-Docker (`svc-docker`), proot-apps, pelorus accessibility bridge.
- GPU acceleration on **X11**: no DRI3 Xvfb patch. The Wayland path is fully
  accelerated on NVIDIA, including NVENC — see [NVIDIA in a Nix
  image](#nvidia-in-a-nix-image).

## Theming

Both Wayland images ship Catppuccin Mocha: JetBrainsMono Nerd Font, Papirus
icons and Catppuccin cursors, from a shared `themePackages` list so the two
cannot drift apart. Seeded configs cover foot, fuzzel and mako.

The niri image keeps noctalia-shell for bar, launcher, notifications and
wallpaper. The Hyprland image uses the conventional stack instead (waybar,
fuzzel, mako, swaybg) with a generated gradient wallpaper.

**The theming is tuned for the software path**, which is still what you get
without a GPU. Blur is off in both images: it is by far the most expensive
effect when llvmpipe draws every frame and x264 encodes it for the browser.
Rounded corners, gradient borders and shadows are close to free and carry the
look on their own. Animations are short on purpose, because every intermediate
frame is one more frame to encode and ship. On an NVIDIA host these constraints
no longer bind, so turning blur back up is reasonable there.

## Hyprland needs a render node

The Hyprland image does **not** start without a GPU:

```
what():  CBackend::create() failed!
```

aquamarine allocates its buffers through GBM, so with no render node there is
no backend, even with `WAYLAND_DISPLAY` pointing at pixelflux's compositor.
niri survives the same conditions because Smithay's winit backend falls back to
software rendering (`error getting EGL device render node`, then Pixman).

Pass a render node in (`--device /dev/dri/renderD128`, or `DRI_NODE`) and
Hyprland works. The niri and i3 images have no such requirement.

## NVIDIA in a Nix image

Hardware rendering and NVENC both work. On a Quadro M1000M (Maxwell, driver
580.178.04) under gpu-operator/CDI, the niri image reaches the same full
hardware path as the upstream Ubuntu webtop:

```
[Wayland] Initializing GL Renderer using device: /dev/dri/renderD128
[Wayland] Nvidia Encoder detected. Initializing NVENC...
[NVENC]   Device 0: Quadro M1000M
[NVENC] Bound to CUDA device via PCI Bus ID: 0000:01:00.0
[Wayland] Decision: Zero-Copy path active.
Stream settings active -> Mode: H264 (NVENC) FullFrame
```

The NVIDIA container toolkit injects the host driver into `/usr/local/lib`, which
a Nix-built image does not search — its GL stack is `/run/opengl-driver/lib` and
carries Mesa only. The `10_nvidia.json` ICD the toolkit drops in names
`libEGL_nvidia.so.0` with no path, so the loader never finds it and rendering
silently falls back to software.

`rootfs/init` detects that and wires four things, because a library path alone
is not enough:

1. `LD_LIBRARY_PATH` so `libEGL_nvidia.so.0` resolves.
2. `GBM_BACKENDS_PATH` pointing at a shim dir holding a `nvidia-drm_gbm.so`.
   That name is what GBM looks for; `GBM_BACKENDS_PATH` **replaces** the default
   search path rather than extending it, so the shim dir also carries symlinks
   to Mesa's own backends, or Mesa can no longer find `dri_gbm.so`.
3. `__EGL_EXTERNAL_PLATFORM_CONFIG_DIRS` with a generated `15_nvidia_gbm.json`
   (→ `libnvidia-egl-gbm.so.1`), which the toolkit does not inject.
4. …and, in the same directory, `10_nvidia_wayland.json`
   (→ `libnvidia-egl-wayland.so.1`). Without it EGL has no
   `EGL_WL_bind_wayland_display` and pixelflux logs
   `Failed to bind EGL to Wayland Display`.

None of this runs unless `/usr/local/lib/libEGL_nvidia.so.0` exists, so the
software path is unchanged on hosts without an NVIDIA GPU.

### The GBM backend is libnvidia-allocator, not libnvidia-egl-gbm

This one cost a while, so it is worth stating plainly. The two libraries have
confusingly similar names and completely different jobs:

| library | exports | role |
| --- | --- | --- |
| `libnvidia-allocator.so.1` | `gbmint_get_backend` | the GBM backend — this is what `nvidia-drm_gbm.so` must point at |
| `libnvidia-egl-gbm.so.1` | `loadEGLExternalPlatform` | the EGL external platform named by `15_nvidia_gbm.json` |

Pointing `nvidia-drm_gbm.so` at `libnvidia-egl-gbm.so.1` fails in a maximally
misleading way. EGL initialises on the NVIDIA GPU, the GL renderer initialises
on the NVIDIA GPU, and only buffer allocation dies — because GBM `dlopen`s the
backend, finds no `gbmint_get_backend`, rejects it, and quietly falls through to
Mesa's `dri_gbm.so` on an NVIDIA render node:

```
[Wayland] Initializing GL Renderer using device: /dev/dri/renderD128
[Wayland] GPU Initialization failed: Failed to allocate GBM buffer.
          Falling back to Software Renderer (Pixman).
```

`rootfs/init` no longer guesses the name. The toolkit already drops a correct
`/usr/local/lib/gbm/nvidia-drm_gbm.so` symlink, so the init resolves that and
only falls back to `libnvidia-allocator.so.1` if it is absent.

Two things that look like the problem but are not:

- **`/dev/dri/card1` is mode 600 and root-owned**, and the desktop runs as `abc`.
  It does not matter. NVIDIA's GBM path goes through the render node plus
  `/dev/nvidia*`, all of which are `crw-rw-rw-`. The KMS card node is never
  opened.
- **`EGL_WL_bind_wayland_display` being unsupported** is not the EGLStreams
  split resurfacing. It is just the missing `10_nvidia_wayland.json` from item 4
  above; add the config and the extension appears.

## Known upstream limit: Hyprland and wl_compositor v6

The Hyprland image starts and then dies:

```
wl_registry#2: error 0: invalid version for global wl_compositor (2):
              expected at most 5, got 6
what():  CBackend::create() failed!
```

Hyprland's aquamarine binds `wl_compositor` at version 6; pixelflux advertises
5. pixelflux calls Smithay's `CompositorState::new`, and the Smithay revision it
already pins also provides `CompositorState::new_v6`, so upstream the fix is one
word. Note Smithay's own caveat: v6 requires `send_surface_state` for clients
using non-default scaling, so it is not a free bump.

Nothing in this flake can work around it — pixelflux is consumed as a prebuilt
wheel (there is no sdist), so changing it means building it from source.
