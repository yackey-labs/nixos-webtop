{
  description = "Nix-built Selkies remote-desktop base image and i3 webtop (a port of linuxserver/docker-baseimage-selkies + docker-webtop:arch-i3)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # scoot ships its own flake, so it is consumed from there rather than
  # re-packaged under nix/ the way selkies, pixelflux and gst-wayland-display
  # are -- none of those has one. Its nixpkgs follows ours: scoot's flake pins
  # a specific nixpkgs revision for its dev VM, and honouring that pin here
  # would put a second glibc, wayland, libinput and udev in an image that
  # already has one of each.
  inputs.scoot.url = "github:scoot-sh/scoot";
  inputs.scoot.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, scoot }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      lib = nixpkgs.lib;
      forAllSystems = f: lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        }));
      # Bound here rather than inside the overlay because the scope down there
      # binds the name `scoot` to this very package: an attribute set is not
      # recursive, so `scoot = scoot.packages...` would in fact resolve, but
      # only for a reader who checks that it is not a `rec`.
      scootFor = system: scoot.packages.${system}.default;
    in
    {
      overlays.default = final: prev: {
        # GStreamer's Wayland GL window has never forwarded keyboard input: in
        # gstglwindow_wayland_egl.c the whole WL_SEAT_CAPABILITY_KEYBOARD block
        # sits inside `#if 0`, referencing a `keyboard_listener` that is never
        # defined and an `input` variable that no longer exists. Pointer input
        # is wired up right next to it, which is why the nested Hyprland desktop
        # had a working mouse and a completely dead keyboard.
        #
        # waylanddisplaysrc turns GstNavigation KeyPress/KeyRelease into evdev
        # scancodes via a table keyed on X keysym names ("Escape", "exclam",
        # "parenleft"), which is exactly what xkb_keysym_get_name produces, so
        # the patch binds wl_keyboard, tracks the xkb keymap and modifier state,
        # and emits those names through gst_gl_window_send_key_event.
        #
        # overrideScope rather than a plain attribute override so every package
        # in the set links the same libgstgl; two copies in one image would be a
        # symlink-farm conflict waiting to happen.
        #
        # Exposed as its OWN attribute rather than replacing gst_all_1. Patching
        # gst_all_1 overlay-wide rebuilds everything that touches GStreamer
        # anywhere in nixpkgs -- the first attempt dragged in ungoogled-chromium,
        # libadwaita, nautilus and zenity, ran for 51 minutes and then failed on
        # zenity, a package no image here even uses for video. Only the
        # hyprland-gst image consumes this set.
        gstWithWaylandKeyboard = prev.gst_all_1.overrideScope (gstFinal: gstPrev: {
          gst-plugins-base = gstPrev.gst-plugins-base.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nix/patches/gst-gl-wayland-keyboard.patch ];
            buildInputs = (old.buildInputs or [ ]) ++ [ final.libxkbcommon ];
          });
        });

        selkiesPackages = lib.makeScope final.newScope (self: {
          inherit (final) noctalia-shell;
          scoot = scootFor final.stdenv.hostPlatform.system;

          # Pinned upstream sources (same commit linuxserver builds from).
          selkiesSrc = final.fetchFromGitHub {
            owner = "selkies-project";
            repo = "selkies";
            rev = "2.0.0";
            hash = "sha256-6PgypByfQkH5RI+ZAkMANCF/R/KtAyno+tFNeIYRcyA=";
          };

          # Python interpreter whose package set carries Selkies' extras. Overriding
          # `python-xlib` here (rather than adding a second package) keeps pynput and
          # selkies on the same python-xlib fork -- which matters more than it
          # looks: pynput is how X11 input injection reaches the desktop, and a
          # pynput built against stock python-xlib would be talking to a
          # different protocol layer than selkies is.
          pythonSelkies = final.python3.override {
            packageOverrides = pself: _psuper: {
              python-xlib = pself.callPackage ./nix/python-xlib-selkies.nix { };
              pixelflux = pself.callPackage ./nix/pixelflux.nix { };
              pcmflux = pself.callPackage ./nix/pcmflux.nix { };
            };
          };
          pixelflux = self.pythonSelkies.pkgs.pixelflux;
          pcmflux = self.pythonSelkies.pkgs.pcmflux;
          selkies = self.callPackage ./nix/selkies.nix { python3 = self.pythonSelkies; };
          selkies-web = self.callPackage ./nix/selkies-web.nix { };
          selkies-addons = self.callPackage ./nix/selkies-addons.nix { };
          nginx-selkies = self.callPackage ./nix/nginx.nix { };
          # GStreamer source element wrapping a Smithay compositor that binds
          # wl_compositor v6, unlike pixelflux's v5. See nix/gst-wayland-display.nix.
          gst-wayland-display = self.callPackage ./nix/gst-wayland-display.nix {
            gst_all_1 = final.gstWithWaylandKeyboard;
            inherit (final) wayland wayland-protocols libxkbcommon
                            libinput udev libdrm libgbm libGL seatd pixman;
          };

          mkSelkiesImage = self.callPackage ./nix/image.nix { };

          # Shared look: one font with glyph coverage for the bars, one icon
          # theme, one cursor theme. Kept in a single list so the niri and
          # Hyprland images cannot drift apart visually.
          themePackages = with final; [
            nerd-fonts.jetbrains-mono
            # ashell draws ALL of its icons (including the launcher button)
            # from "Symbols Nerd Font" by family name; without this package
            # fc-match falls back to DejaVu and every glyph comes out blank.
            nerd-fonts.symbols-only
            papirus-icon-theme
            # The bare `catppuccin-cursors` attribute is an aggregate and ships
            # NO share/icons theme directory -- with it alone /usr/share/icons
            # held only Adwaita, breeze and Papirus, so XCURSOR_THEME below
            # pointed at a theme that did not exist and the pointer never drew.
            # The per-flavour variant is what actually installs
            # share/icons/catppuccin-mocha-dark-cursors.
            catppuccin-cursors.mochaDark
            adwaita-icon-theme
          ];

          # linuxserver/baseimage-selkies equivalent: openbox + st/xterm.
          image-base = self.mkSelkiesImage {
            name = "selkies-nix-base";
            title = "Selkies";
            startwm = ./rootfs/defaults/startwm-openbox.sh;
            configTemplates = { ghostty = ./rootfs/config/ghostty; };
            extraEnv = [ "TERMINAL=ghostty" ];
            extraPackages = with final; [
              ghostty
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ];
          };

          # linuxserver/webtop:arch-i3 equivalent: i3 + xfce4-terminal + chromium.
          image-webtop-i3 = self.mkSelkiesImage {
            name = "selkies-nix-webtop-i3";
            title = "Nix i3";
            startwm = ./rootfs/defaults/startwm-i3.sh;
            configTemplates = { ghostty = ./rootfs/config/ghostty; };
            extraEnv = [ "TERMINAL=ghostty" ];
            extraPackages = with final; [
              i3
              i3status
              dmenu
              ghostty
              xfce4-terminal
              xfce.xfconf
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ];
          };

          # niri (scrolling Wayland compositor) + noctalia-shell (Quickshell desktop shell),
          # nested inside pixelflux's compositor via niri's winit backend.
          image-webtop-niri = self.mkSelkiesImage {
            name = "selkies-nix-webtop-niri";
            title = "Nix niri";
            wayland = true;
            # pixelflux's compositor takes wayland-1; nested niri lands on wayland-2
            # (same index linuxserver uses for nested sway).
            waylandSocketIndex = 2;
            startwm = ./rootfs/defaults/startwm-niri.sh;
            configTemplates = {
              niri = ./rootfs/config/niri;
              ghostty = ./rootfs/config/ghostty;
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
            };
            extraEnv = [ "TERMINAL=ghostty" "XDG_CURRENT_DESKTOP=niri" ];
            extraPackages = (with final; [
              niri
              noctalia-shell
              xwayland-satellite
              ghostty
              foot
              fuzzel
              xfce4-terminal
              xfce.xfconf
              nautilus
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ]) ++ self.themePackages;
          };

          # Hyprland + waybar, nested the same way niri is. Where the niri image
          # leans on noctalia-shell for bar/launcher/notifications/wallpaper,
          # this one uses the conventional Hyprland stack: waybar, fuzzel, mako
          # and swaybg. Same Catppuccin Mocha palette in both.
          image-webtop-hyprland = self.mkSelkiesImage {
            name = "selkies-nix-webtop-hyprland";
            title = "Nix Hyprland";
            wayland = true;
            waylandSocketIndex = 2;
            startwm = ./rootfs/defaults/startwm-hyprland.sh;
            configTemplates = {
              hypr = ./rootfs/config/hypr;
              waybar = ./rootfs/config/waybar;
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
              mako = ./rootfs/config/mako;
              ghostty = ./rootfs/config/ghostty;
            };
            extraEnv = [
              "TERMINAL=ghostty"
              "XDG_CURRENT_DESKTOP=Hyprland"
              "XCURSOR_THEME=catppuccin-mocha-dark-cursors"
              "XCURSOR_SIZE=24"
            ];
            extraPackages = (with final; [
              hyprland
              waybar
              mako
              swaybg
              fuzzel
              ghostty
              foot
              xwayland-satellite
              nautilus
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ]) ++ self.themePackages;
          };

          # scoot (scrolling-tiling Wayland compositor, niri-shaped) with a
          # deliberately thin desktop: ashell (bar), fuzzel (launcher) and
          # awww (wallpaper), nested the same way the niri image nests.
          # scoot was written with this image's exact shape in mind: it
          # composites with pixman on the CPU, so it needs no GPU and no EGL,
          # and it exposes a control socket that can inject keys, click and
          # screenshot -- a session an agent can drive as easily as a person.
          #
          # There is deliberately NO desktop shell here (no noctalia-shell):
          # the bar is a plain layer-shell client whose buttons take the
          # same click path window buttons do, the launcher is spawned
          # fresh per use, and the wallpaper is a static image. Fewer moving
          # pieces between a click and its target.
          #
          # There is NO XWayland here (scoot has none), so xwayland-satellite
          # is absent and every application in this list is Wayland-native.
          image-webtop-scoot = self.mkSelkiesImage {
            name = "selkies-nix-webtop-scoot";
            title = "Nix scoot";
            wayland = true;
            waylandSocketIndex = 2;
            # Nothing in this image can reach an X server: scoot has no
            # XWayland, so Xvfb, openbox, st, xterm, xdotool, xrandr and the
            # rest of the X userland would be dead weight. This is the only
            # image that can say that.
            x11 = false;
            startwm = ./rootfs/defaults/startwm-scoot.sh;
            configTemplates = {
              scoot = ./rootfs/config/scoot;
              ashell = ./rootfs/config/ashell;
              ghostty = ./rootfs/config/ghostty;
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
            };
            extraEnv = [
              "TERMINAL=ghostty"
              "XDG_CURRENT_DESKTOP=scoot"
              "XCURSOR_THEME=catppuccin-mocha-dark-cursors"
              "XCURSOR_SIZE=24"
              # Phones report DPR 2-3, so without this the coded stream is
              # CSS-size x DPR (2.7+ MP on an iPhone) while iOS browsers get
              # a Baseline-L3.0 decoder config (max ~0.4 MP) -- WebKit then
              # decodes to black with a live cursor. CSS scaling sends the
              # CSS size and stretches locally, which fits the decoder and
              # is 4-9x fewer pixels to encode. Desktop users can toggle it
              # back off in the sidebar's screen settings.
              "SELKIES_USE_CSS_SCALING=true"
            ];
            extraPackages = (with final; [
              ghostty
              foot
              fuzzel
              ashell
              awww
              nautilus
              chromium
              self.chromiumWrapped
              self.wtypeViaScoot
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ]) ++ [ self.scoot ] ++ self.themePackages;
          };

          # Hyprland on gst-wayland-display rather than pixelflux, to get a
          # wl_compositor v6 parent. See rootfs/defaults/startwm-hyprland-gst.sh.
          image-webtop-hyprland-gst = self.mkSelkiesImage {
            name = "selkies-nix-webtop-hyprland-gst";
            title = "Nix Hyprland (gst)";
            wayland = true;
            waylandSocketIndex = 2;
            startwm = ./rootfs/defaults/startwm-hyprland-gst.sh;
            configTemplates = {
              hypr = ./rootfs/config/hypr;
              waybar = ./rootfs/config/waybar;
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
              mako = ./rootfs/config/mako;
              ghostty = ./rootfs/config/ghostty;
            };
            extraEnv = [
              "TERMINAL=ghostty"
              "XDG_CURRENT_DESKTOP=Hyprland"
              "XCURSOR_THEME=catppuccin-mocha-dark-cursors"
              "XCURSOR_SIZE=24"
              # gst-launch needs to find the plugin and its dependencies.
              "GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib/gstreamer-1.0"
              # $HOME is /config, which is the PVC. Putting mise's shims and
              # ~/.local/bin ahead of the image means languages and Claude Code
              # install once, persist across image rebuilds, and update
              # themselves without one. Overrides imageEnv's PATH, so the image
              # directories are repeated here.
              "PATH=/config/.local/bin:/config/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
              "MISE_TRUSTED_CONFIG_PATHS=/config"
            ];
            extraPackages = (with final; [
              hyprland waybar mako swaybg fuzzel foot
              xwayland-satellite nautilus chromium
              # Terminal of choice.
              ghostty
              # mise installs language runtimes into $HOME, which is the PVC, so
              # they survive image rebuilds and update without one. It compiles
              # most runtimes from source, hence the toolchain below.
              mise
              gcc gnumake pkg-config binutils patch
              openssl zlib libffi readline ncurses bzip2 xz sqlite
              git unzip
              # Claude Code installs into $HOME/.local/bin and self-updates.
              nodejs_22
              self.chromiumWrapped
              # .out, NOT the default output. gst_all_1.gstreamer's default is
              # the "-bin" output, which carries gst-launch/gst-inspect but no
              # plugins -- so libgstcoreelements.so was absent and the pipeline
              # died with `no element "fakesink"` while 109 other plugins from
              # base/good were present and waylanddisplaysrc inspected fine.
              gstWithWaylandKeyboard.gstreamer.out
              gstWithWaylandKeyboard.gstreamer
              gstWithWaylandKeyboard.gst-plugins-base
              gstWithWaylandKeyboard.gst-plugins-good
              # gst-plugins-bad was here only for waylandsink, which is gone --
              # it cannot forward input, so the pipeline uses glimagesink from
              # -base instead. Dropping it also keeps the rebuild triggered by
              # the -base patch above down to a sane size.
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
              (writeShellScriptBin "dev-setup" (builtins.readFile ./rootfs/defaults/dev-setup.sh))
            ]) ++ [ self.gst-wayland-display ] ++ self.themePackages;
          };

          # Selkies types text into the session by shelling out to `wtype`,
          # which speaks virtual-keyboard-v1 -- a protocol scoot deliberately
          # does not implement. scoot's control socket does the same job and
          # does it better: `scoot msg type` types on the *active* keyboard
          # layout and handles shifted characters, dead keys and compose
          # sequences itself, rather than synthesising raw keycodes and hoping
          # the layout agrees.
          #
          # This is what makes a phone keyboard and a clipboard paste work in
          # the scoot image -- the same thing commit 32ac3a1 had to fix by
          # hand for Hyprland, except here there is a real API for it.
          #
          # hiPrio because base `wtype` is in every image; buildEnv resolves
          # the collision in this one's favour.
          wtypeViaScoot = final.lib.hiPrio (final.writeShellScriptBin "wtype" ''
            # Selkies calls this two ways: `wtype CHAR` for a keysym it could
            # not map, and `wtype -- TEXT` for a batch, which is the shape a
            # clipboard paste and a phone keyboard arrive in. After `--`
            # everything is literal, so a pasted "-n" is typed, not rejected.
            literal=0
            if [ "''${1:-}" = "--" ]; then literal=1; shift; fi
            if [ "$literal" = 0 ]; then
              for arg in "$@"; do
                case "$arg" in
                  # -k/-M/-m/-P/-p/-s are wtype's key and modifier options.
                  # Nothing in Selkies passes them, and typing a flag as
                  # literal text would be a silent wrong answer.
                  -*) echo "wtype: unsupported option $arg (this is scoot's shim)" >&2; exit 64 ;;
                esac
              done
            fi
            [ "$#" -gt 0 ] || exit 0
            exec ${self.scoot}/bin/scoot msg type "$*"
          '');

          # Mirrors linuxserver's /usr/bin/chromium wrapper (plus Wayland detection).
          chromiumWrapped = final.lib.hiPrio (final.writeShellScriptBin "chromium" ''
            if ! ${final.procps}/bin/pgrep -x chromium >/dev/null; then
              rm -f "$HOME/.config/chromium/Singleton"*
            fi
            OZONE=""
            if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
              OZONE="--ozone-platform=wayland"
            fi
            exec ${final.chromium}/bin/chromium \
              --password-store=basic \
              --no-sandbox \
              --test-type \
              --disable-dev-shm-usage \
              $OZONE \
              "$@"
          '');
        });
      };

      packages = forAllSystems (pkgs: {
        inherit (pkgs.selkiesPackages)
          selkies selkies-web selkies-addons pixelflux pcmflux nginx-selkies
          gst-wayland-display
          scoot
          image-base image-webtop-i3 image-webtop-niri image-webtop-hyprland
          image-webtop-hyprland-gst image-webtop-scoot;
        default = pkgs.selkiesPackages.image-webtop-i3;
      });

      # `nix develop` gives you the python env + tooling for hacking on the flake.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.selkiesPackages.selkies pkgs.prefetch-npm-deps pkgs.nix-prefetch-git ];
        };
      });
    };
}
