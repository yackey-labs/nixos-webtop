{
  description = "Nix-built Selkies remote-desktop base image and i3 webtop (a port of linuxserver/docker-baseimage-selkies + docker-webtop:arch-i3)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      lib = nixpkgs.lib;
      forAllSystems = f: lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        }));
    in
    {
      overlays.default = final: prev: {
        selkiesPackages = lib.makeScope final.newScope (self: {
          # Pinned upstream sources (same commit linuxserver builds from).
          selkiesSrc = final.fetchFromGitHub {
            owner = "selkies-project";
            repo = "selkies";
            rev = "348bc4f61da66198573e7e57db9a266aca1991d5";
            hash = "sha256-buiWdWvweSIGG/N9QRBkxlBcXvPbFjNIC6zyZydpYuc=";
          };

          # Python interpreter whose package set carries Selkies' extras. Overriding
          # `python-xlib` here (rather than adding a second package) keeps pynput and
          # selkies on the same python-xlib fork.
          pythonSelkies = final.python3.override {
            packageOverrides = pself: psuper: {
              python-xlib = pself.callPackage ./nix/python-xlib-selkies.nix { xlib = psuper.python-xlib; };
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

          mkSelkiesImage = self.callPackage ./nix/image.nix { };

          # Shared look: one font with glyph coverage for the bars, one icon
          # theme, one cursor theme. Kept in a single list so the niri and
          # Hyprland images cannot drift apart visually.
          themePackages = with final; [
            nerd-fonts.jetbrains-mono
            papirus-icon-theme
            catppuccin-cursors
            adwaita-icon-theme
          ];

          # linuxserver/baseimage-selkies equivalent: openbox + st/xterm.
          image-base = self.mkSelkiesImage {
            name = "selkies-nix-base";
            title = "Selkies";
            startwm = ./rootfs/defaults/startwm-openbox.sh;
          };

          # linuxserver/webtop:arch-i3 equivalent: i3 + xfce4-terminal + chromium.
          image-webtop-i3 = self.mkSelkiesImage {
            name = "selkies-nix-webtop-i3";
            title = "Nix i3";
            startwm = ./rootfs/defaults/startwm-i3.sh;
            extraEnv = [ "TERMINAL=xfce4-terminal" ];
            extraPackages = with final; [
              i3
              i3status
              dmenu
              xfce4-terminal
              xfce.xfconf
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${xfce4-terminal}/bin/xfce4-terminal "$@"'')
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
              foot = ./rootfs/config/foot;
              fuzzel = ./rootfs/config/fuzzel;
            };
            extraEnv = [ "TERMINAL=foot" "XDG_CURRENT_DESKTOP=niri" ];
            extraPackages = (with final; [
              niri
              noctalia-shell
              xwayland-satellite
              foot
              fuzzel
              xfce4-terminal
              xfce.xfconf
              nautilus
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${foot}/bin/foot "$@"'')
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
            };
            extraEnv = [
              "TERMINAL=foot"
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
              foot
              xwayland-satellite
              nautilus
              chromium
              self.chromiumWrapped
              (writeShellScriptBin "x-terminal-emulator" ''exec ${foot}/bin/foot "$@"'')
            ]) ++ self.themePackages;
          };

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
          image-base image-webtop-i3 image-webtop-niri image-webtop-hyprland;
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
