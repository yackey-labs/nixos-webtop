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
      scootbgFor = system: scoot.packages.${system}.scootbg;
      scootbarFor = system: scoot.packages.${system}.scootbar;
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
          # scoot's own wallpaper daemon, from the same flake input, so it
          # always matches the compositor it was built against.
          scootbg = scootbgFor final.stdenv.hostPlatform.system;
          # ...and its status bar, likewise.
          scootbar = scootbarFor final.stdenv.hostPlatform.system;

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

          # Sibling builder for the VNC image (headless scoot + wayvnc +
          # noVNC): separate from mkSelkiesImage on purpose -- different
          # services, different ports, no Selkies/nginx/Xvfb.
          mkVncImage = self.callPackage ./nix/vnc-image.nix { };

          # Shared look: one font with glyph coverage for the bars, one icon
          # theme, one cursor theme. Kept in a single list so the niri and
          # Hyprland images cannot drift apart visually.
          themePackages = with final; [
            nerd-fonts.jetbrains-mono
            # Anything that asks fontconfig for "Symbols Nerd Font" by family
            # name gets DejaVu without this package, and every icon glyph
            # comes out blank.
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
          # deliberately thin desktop: scootbar (bar), fuzzel (launcher) and
          # scootbg (wallpaper), nested the same way the niri image nests.
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
          # There is NO XWayland here (scoot's [xwayland] stays off -- an
          # extra ~55 MB server process plus the X userland, for zero X
          # applications), so xwayland-satellite is absent and every
          # application in this list is Wayland-native.
          #
          # The look (scoot + bar + foot + starship + Helix + btop + lazygit
          # themes, one of radial-burst, music-desk, vinyl-sunset, moonrise) is picked
          # at run time with SCOOT_LOOK (default radial-burst); see
          # rootfs/defaults/startwm-scoot.sh and NOTICE.scoot-looks.
          image-webtop-scoot = self.mkSelkiesImage {
            name = "selkies-nix-webtop-scoot";
            title = "Nix scoot";
            wayland = true;
            waylandSocketIndex = 2;
            # Nothing in this image can reach an X server: [xwayland] is off
            # (see above), so Xvfb, openbox, st, xterm, xdotool, xrandr and
            # the rest of the X userland would be dead weight. This is the
            # only image that can say that.
            x11 = false;
            startwm = ./rootfs/defaults/startwm-scoot.sh;
            configTemplates = {
              # No scoot or foot here: startwm-scoot.sh seeds the picked
              # look's scoot.toml / bar.toml / foot.ini (plus starship, Helix,
              # btop, lazygit and the bar's load.sh/cpu.sh helpers) into
              # ~/.config on first use and whenever SCOOT_LOOK changes, so
              # one image carries all four looks.
              ghostty = ./rootfs/config/ghostty;
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
              # The pointer you see is pixelflux's (scoot --nested never sets
              # a host cursor), delivered to the browser at the theme's
              # nominal size whatever the output scale, and drawn there at
              # the page's density. Left on auto (24) that is a 32 px sprite:
              # 16 CSS px in HiDPI mode (density 2) but 32 under CSS scaling
              # (density 1) -- a huge pointer on a phone until HiDPI was
              # toggled. A base of 12 is scaled by Selkies with the DPI
              # (12 at 96, 24 at 192), so both modes land on ~16 CSS px.
              "SELKIES_CURSOR_SIZE=12"
              # scootbar takes a font FILE, not a family name (no
              # fontconfig), and none of its well-known paths exist here.
              "SCOOTBAR_FONT=${final.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf"
            ];
            extraPackages = (with final; [
              ghostty
              foot
              fuzzel
              nautilus
              chromium
              # The looks theme these too, so they ride along: starship (the
              # prompt), helix (the editor), btop (the monitor) and lazygit.
              starship
              helix
              btop
              lazygit
              self.chromiumWrapped
              self.wtypeViaScoot
              self.scootBarLook
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ]) ++ [ self.scoot self.scootbg self.scootbar ] ++ self.themePackages;
          };

          # Scoot over VNC: the same scrolling-tiling session as
          # image-webtop-scoot (same four SCOOT_LOOK looks from the same
          # shared seeding code, same Alt+Super doubled binds), but scoot
          # runs --headless directly -- no pixelflux, no nested host -- with
          # [virtual_input] enabled, wayvnc (nixpkgs, >= 0.9) captures its
          # virtual outputs, and noVNC (websockify) serves the desktop to a
          # browser at http://host:6080/ with no client install. Native VNC
          # clients use port 5900.
          #
          # Why this exists next to the Selkies image: one compositor instead
          # of two (the Selkies image nests scoot inside pixelflux's own
          # compositor), and VNC sends only damage -- so idle and typing
          # should cost less. Video and heavy scrolling should cost MORE:
          # Selkies streams WebRTC H.264 while VNC ships raw-ish
          # framebuffer updates. Measured per workload in the README's
          # benchmark table -- the honest numbers, not the theory.
          #
          # Security posture, stated loudly (also in the README): VNC has NO
          # AUTH by default and binds loopback only (VNC_LISTEN=127.0.0.1).
          # The browser path always works (in-container proxy); a native
          # client needs VNC_LISTEN=0.0.0.0, and then either host-loopback
          # publishing plus ssh -L, or VNC_PASSWORD. scoot's remote input
          # never works while the session is locked, whatever VNC does.
          #
          # Audio: there is none. RFB carries no audio channel, so this
          # image ships no audio daemon and nothing for it -- PulseAudio is
          # present as a package only so applications that probe it (like
          # Chromium) still start; what they play goes nowhere.
          #
          # Output size is a FIXED configured size (VNC_WIDTH/VNC_HEIGHT,
          # default 1280x800; SELKIES_MANUAL_WIDTH/HEIGHT honored as
          # aliases): noVNC's resize cannot drive scoot's headless output
          # size -- ExtendedDesktopSize has no path to it (no
          # output-management protocol for wayvnc to speak; scoot sizes
          # headless outputs from its flags alone) -- so the browser scales
          # the framebuffer to its window locally instead.
          image-scoot-vnc = self.mkVncImage {
            name = "scoot-vnc";
            title = "Scoot VNC";
            startwm = ./rootfs/defaults/startwm-scoot-vnc.sh;
            configTemplates = {
              ghostty = ./rootfs/config/ghostty;
              fuzzel = ./rootfs/config/fuzzel;
            };
            extraEnv = [
              "TERMINAL=ghostty"
              "XDG_CURRENT_DESKTOP=scoot"
              "XCURSOR_THEME=catppuccin-mocha-dark-cursors"
              "XCURSOR_SIZE=24"
              # scootbar takes a font FILE, not a family name (no
              # fontconfig), and none of its well-known paths exist here.
              "SCOOTBAR_FONT=${final.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf"
            ];
            extraPackages = (with final; [
              wayvnc
              novnc
              python3Packages.websockify
              ghostty
              foot
              fuzzel
              nautilus
              chromium
              # The looks theme these too, so they ride along: starship (the
              # prompt), helix (the editor), btop (the monitor) and lazygit.
              starship
              helix
              btop
              lazygit
              self.chromiumWrapped
              self.scootBarLook
              (writeShellScriptBin "x-terminal-emulator" ''exec ${ghostty}/bin/ghostty "$@"'')
            ]) ++ [ self.scoot self.scootbg self.scootbar ] ++ self.themePackages;
          };

          # Scoot dev flavour: the same nested session minus everything under
          # test. No Chromium, no file manager, no bar, no wallpaper -- just
          # foot, fuzzel and the control socket, so rebuilds stay small and
          # local checkouts of scoot (and later scootbar/scootbg) slot in via
          # --override-input without fighting the things they replace:
          #   ./build.sh image-scoot-dev
          #   nix build .#image-scoot-dev --override-input scoot path:../scoot
          # Roughly half the unpacked size of image-webtop-scoot, and shares
          # most layers with it, so keeping both in the registry is cheap.
          image-scoot-dev = self.mkSelkiesImage {
            name = "selkies-nix-scoot-dev";
            title = "Scoot dev";
            wayland = true;
            waylandSocketIndex = 2;
            # Same reasoning as the prod scoot image: nothing here can reach
            # an X server, so the X userland stays out.
            x11 = false;
            startwm = ./rootfs/defaults/startwm-scoot-dev.sh;
            configTemplates = {
              scoot = ./rootfs/config/scoot;
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
            };
            extraEnv = [
              "TERMINAL=foot"
              "XDG_CURRENT_DESKTOP=scoot"
              "XCURSOR_THEME=catppuccin-mocha-dark-cursors"
              "XCURSOR_SIZE=24"
              # Same phone-decoder reasoning as the prod image: CSS scaling
              # keeps the coded stream inside iOS's Baseline-L3.0 budget.
              "SELKIES_USE_CSS_SCALING=true"
              # Same pointer-size reasoning as the prod image.
              "SELKIES_CURSOR_SIZE=12"
            ];
            extraPackages = (with final; [
              foot
              fuzzel
              self.wtypeViaScoot
              # Kept deliberately small: one terminal font and one cursor
              # theme. No icon themes -- nothing here renders icons (no bar,
              # no file manager); hicolor from the base packages covers theme
              # inheritance lookups.
              nerd-fonts.jetbrains-mono
              catppuccin-cursors.mochaDark
              (writeShellScriptBin "x-terminal-emulator" ''exec ${foot}/bin/foot "$@"'')
            ]) ++ [ self.scoot ];
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

          # How the bar starts, in one place: scoot's [autostart] runs
          # `spawn scoot-bar-look` (an action string splits on whitespace and
          # never sees a shell, so the font store path cannot live in the
          # config), and the session script's supervision loop calls the same
          # wrapper when the bar is missing. The config file is the default
          # path (~/.config/scoot/bar.toml), seeded per look by
          # startwm-scoot.sh; --font names the image's Nerd font file, which
          # the look files deliberately leave out (a store path is not
          # portable). Extra arguments pass through to `scootbar daemon`.
          scootBarLook = final.writeShellScriptBin "scoot-bar-look" ''
            exec ${self.scootbar}/bin/scootbar daemon --font "$SCOOTBAR_FONT" "$@"
          '';

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
          scoot scootbg scootbar
          image-base image-webtop-i3 image-webtop-niri image-webtop-hyprland
          image-webtop-hyprland-gst image-webtop-scoot image-scoot-dev
          image-scoot-vnc;
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
