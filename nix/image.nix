# Builds an OCI image that mirrors linuxserver/docker-baseimage-selkies, but
# every binary comes from nixpkgs and the filesystem is assembled with
# dockerTools.buildLayeredImage. Process supervision is s6-svscan (PID 1).
{ lib, pkgs, dockerTools, buildEnv, runCommand, writeText, writeShellScriptBin
, selkies, selkies-web, selkies-addons, nginx-selkies }:

{ name
, tag ? "latest"
, title ? "Selkies"
, startwm                       # path to the startwm.sh that launches the WM/DE
, wayland ? false               # true: pixelflux's built-in compositor instead of Xvfb (PIXELFLUX_WAYLAND)
, waylandSocketIndex ? 0        # wayland-N socket of the *nested* compositor (clipboard/wtype target)
, configTemplates ? { }         # { "niri" = ./dir; } -> copied to $HOME/.config/niri on first run
, extraPackages ? [ ]
, extraEnv ? [ ]
, extraRoot ? [ ]               # extra derivations copied onto /
, maxLayers ? 110
}:
let
  inherit (pkgs) xorg;

  basePackages = with pkgs; [
    # core userland
    bashInteractive coreutils findutils gnugrep gnused gawk which less file
    procps psmisc util-linux shadow sudo curl wget openssl gnutar gzip xz bzip2
    iproute2 nano tzdata cacert glibcLocales glibc.bin
    # supervision
    s6 execline
    # selkies stack
    selkies selkies-web selkies-addons nginx-selkies
    pulseaudio dbus
    # X11
    xorg-server xorg.xrandr xorg.xset xorg.xrdb xorg.xauth xorg.xhost xorg.xdpyinfo
    xorg.xsetroot xorg.xprop xorg.xwininfo libxcvt xdotool xsettingsd
    xorg.fontmiscmisc xorg.fontcursormisc xkeyboard_config
    xclip xsel wl-clipboard wtype wlr-randr xdg-utils
    # base window manager + terminals (webtop variants add their own on top)
    openbox st xterm
    # graphics / fonts / themes
    mesa libGL libglvnd libva vulkan-loader
    fontconfig dejavu_fonts noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji
    hicolor-icon-theme adwaita-icon-theme gsettings-desktop-schemas glib dconf
    shared-mime-info
  ] ++ extraPackages;

  # /usr is a symlink farm over every package's bin/share/lib/etc.
  rootEnv = buildEnv {
    name = "${name}-root-env";
    paths = basePackages;
    pathsToLink = [ "/bin" "/sbin" "/share" "/lib" "/libexec" "/etc" ];
    ignoreCollisions = true;
  };

  fontsConf = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [ dejavu_fonts noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji ];
  };

  # linuxserver patches openbox's rc.xml: no icon in title bar, everything
  # maximized, ctrl+shift+d toggles decorations, one desktop.
  openboxRc = runCommand "openbox-rc.xml" { } ''
    sed \
      -e 's/NLIMC/NLMC/g' \
      -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
      -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
      -e 's|<number>4</number>|<number>1</number>|' \
      ${pkgs.openbox}/etc/xdg/openbox/rc.xml > $out
  '';

  etcFiles = runCommand "${name}-etc" { } ''
    mkdir -p $out/etc/{pam.d,fonts,xdg/openbox,ssl/certs,sudoers.d}

    cat > $out/etc/passwd <<'PW'
    root:x:0:0:root:/root:/bin/bash
    abc:x:911:911::/config:/bin/bash
    messagebus:x:4:4::/run/dbus:/bin/false
    nobody:x:65534:65534:nobody:/nonexistent:/bin/false
    PW
    cat > $out/etc/group <<'GR'
    root:x:0:
    messagebus:x:4:
    audio:x:29:abc
    video:x:44:abc
    input:x:104:abc
    render:x:105:abc
    users:x:100:abc
    wheel:x:998:abc
    abc:x:911:
    nobody:x:65534:
    nogroup:x:65533:
    GR
    cat > $out/etc/shadow <<'SH'
    root:!:19000:0:99999:7:::
    abc:!:19000:0:99999:7:::
    messagebus:!:19000:0:99999:7:::
    nobody:!:19000:0:99999:7:::
    SH
    cp $out/etc/group $out/etc/gshadow
    sed -i 's/:x:/:!::/' $out/etc/gshadow

    cat > $out/etc/sudoers <<'SD'
    Defaults env_reset
    Defaults secure_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    root ALL=(ALL:ALL) ALL
    abc ALL=(ALL) NOPASSWD: ALL
    @includedir /etc/sudoers.d
    SD

    for f in sudo other login su; do
      cat > $out/etc/pam.d/$f <<'PAM'
    auth     sufficient pam_permit.so
    account  required   pam_permit.so
    password required   pam_deny.so
    session  required   pam_permit.so
    PAM
    done

    cat > $out/etc/nsswitch.conf <<'NS'
    passwd: files
    group: files
    shadow: files
    hosts: files dns
    networks: files
    NS
    cat > $out/etc/os-release <<'OS'
    NAME="NixOS (container)"
    ID=nixos
    PRETTY_NAME="Nix-built Selkies image"
    OS
    cat > $out/etc/login.defs <<'LD'
    UID_MIN 1000
    UID_MAX 60000
    GID_MIN 1000
    GID_MAX 60000
    LD
    cat > $out/etc/profile <<'PR'
    export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    PR
    echo "selkies" > $out/etc/hostname
    cp ${fontsConf} $out/etc/fonts/fonts.conf
    cp ${openboxRc} $out/etc/xdg/openbox/rc.xml
    cp ${pkgs.openbox}/etc/xdg/openbox/menu.xml $out/etc/xdg/openbox/menu.xml
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-bundle.crt
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt
  '';

  # Filesystem skeleton: /usr -> nix env, /bin, /lib64 loaders, /defaults, /init, s6 services.
  skeleton = runCommand "${name}-skeleton" { } ''
    mkdir -p $out/usr $out/lib $out/lib64 $out/defaults $out/etc/s6 $out/usr/local/bin $out/opt/lib

    ln -s ${rootEnv}/bin     $out/usr/bin
    ln -s ${rootEnv}/sbin    $out/usr/sbin
    ln -s ${rootEnv}/share   $out/usr/share
    ln -s ${rootEnv}/lib     $out/usr/lib
    ln -s ${rootEnv}/libexec $out/usr/libexec
    ln -s ${rootEnv}/etc     $out/usr/etc
    ln -s usr/bin            $out/bin
    ln -s usr/sbin           $out/sbin

    # ELF loaders so prebuilt (non-Nix) binaries dropped into the container can run.
    for l in ${pkgs.glibc}/lib/ld-linux*; do
      ln -s "$l" $out/lib/;  ln -s "$l" $out/lib64/
    done

    # NixOS-style GL driver location so mesa/libglvnd find swrast.
    mkdir -p $out/run
    ln -s ${pkgs.mesa} $out/run/opengl-driver

    # gamepad helpers (same layout linuxserver uses)
    mkdir -p $out/usr/local/lib
    ln -s ${selkies-addons}/lib/selkies_joystick_interposer.so $out/usr/local/lib/selkies_joystick_interposer.so
    ln -s ${selkies-addons}/lib/libudev.so.1.0.0-fake $out/opt/lib/libudev.so.1.0.0-fake

    cp -r ${../rootfs/defaults}/. $out/defaults/
    cp ${startwm} $out/defaults/startwm.sh
    mkdir -p $out/defaults/config
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: d: "cp -r ${d} $out/defaults/config/${n}") configTemplates)}
    cp -r ${../rootfs/etc/s6}/. $out/etc/s6/
    cp ${../rootfs/init} $out/init
    chmod +x $out/init $out/defaults/*.sh
    find $out/etc/s6 -name run -exec chmod +x {} +

    # sudo must be a real setuid file, not a store symlink; perms set in fakeRootCommands.
    cp ${pkgs.sudo}/bin/sudo $out/usr/local/bin/sudo
  '';

  imageEnv = [
    "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "HOME=/config"
    "DISPLAY=:1"
    "TITLE=${title}"
    "LANG=en_US.UTF-8"
    "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
    "TZDIR=${pkgs.tzdata}/share/zoneinfo"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
    "XDG_DATA_DIRS=/usr/share:/usr/local/share"
    "XDG_CONFIG_DIRS=/etc/xdg:/usr/etc/xdg"
    "FONTCONFIG_FILE=/etc/fonts/fonts.conf"
    "XCURSOR_PATH=/usr/share/icons"
    "XCURSOR_THEME=Adwaita"
    "XCURSOR_SIZE=24"
    "XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb"
    "XVFB_FONT_PATH=${xorg.fontmiscmisc}/lib/X11/fonts/misc,${xorg.fontcursormisc}/lib/X11/fonts/misc"
    "GIO_EXTRA_MODULES=${pkgs.dconf.lib}/lib/gio/modules"
    "GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas"
    "LIBGL_ALWAYS_SOFTWARE=1"
    "PULSE_RUNTIME_PATH=/run/pulse"
    "PULSE_SERVER=unix:/run/pulse/native"
    "SELKIES_ENCODER=x264enc,jpeg"
    "SELKIES_INTERPOSER=/usr/local/lib/selkies_joystick_interposer.so"
    "NVIDIA_DRIVER_CAPABILITIES=all"
    "DISABLE_ZINK=false"
    "DISABLE_DRI3=false"
    "TERMINAL=st"
  ] ++ lib.optionals wayland [
    "PIXELFLUX_WAYLAND=true"
    "SELKIES_WAYLAND_SOCKET_INDEX=${toString waylandSocketIndex}"
    "SELKIES_SECOND_SCREEN=false"
    "XDG_SESSION_TYPE=wayland"
  ] ++ extraEnv;
in
dockerTools.buildLayeredImage {
  inherit name tag maxLayers;
  created = "now";

  contents = [ skeleton etcFiles ] ++ extraRoot;

  extraCommands = ''
    mkdir -p tmp config run/service var/log var/tmp var/cache proot-apps
    chmod 1777 tmp var/tmp
  '';

  # `contents` are symlinked into the image root. Files that must be mutable at
  # runtime (PUID/PGID mapping) or carry special modes (setuid sudo) need to be
  # real files, so replace those symlinks with copies here.
  fakeRootCommands = ''
    for f in etc/passwd etc/group etc/shadow etc/gshadow etc/sudoers etc/nsswitch.conf etc/hostname usr/local/bin/sudo; do
      target="$(readlink -f "$f")"
      rm -f "$f"
      cp "$target" "$f"
      chown 0:0 "$f"
    done
    chmod 0644 etc/passwd etc/group etc/nsswitch.conf etc/hostname
    chmod 0640 etc/shadow etc/gshadow
    chmod 0440 etc/sudoers
    chmod 4755 usr/local/bin/sudo
    chown 911:911 config
  '';

  config = {
    Cmd = [ "/init" ];
    Env = imageEnv;
    ExposedPorts = { "3000/tcp" = { }; "3001/tcp" = { }; };
    Volumes = { "/config" = { }; };
    WorkingDir = "/config";
    Labels = {
      "org.opencontainers.image.title" = title;
      "org.opencontainers.image.description" = "Selkies remote desktop built with Nix (port of linuxserver/docker-baseimage-selkies)";
      "org.opencontainers.image.source" = "https://github.com/linuxserver/docker-baseimage-selkies";
    };
  };
}
