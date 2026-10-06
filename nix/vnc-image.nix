# Builds an OCI image for the scoot VNC desktop: headless scoot + wayvnc +
# noVNC, supervised by s6-svscan (PID 1). Sibling of nix/image.nix
# (mkSelkiesImage), deliberately separate rather than a flag on it: the
# Selkies images carry pixelflux/nginx/Xvfb and expose 3000/3001, while this
# one carries wayvnc/websockify/noVNC and exposes 5900/6080. Sharing one
# function would thread VNC conditionals through every Selkies service.
{ lib, pkgs, dockerTools, buildEnv, runCommand }:

{ name
, tag ? "latest"
, title ? "Scoot VNC"
, startwm                       # path to the startwm.sh that launches scoot headless
, configTemplates ? { }         # { "ghostty" = ./dir; } -> tracked into $HOME/.config/<app>
, extraPackages ? [ ]
, extraEnv ? [ ]
, extraRoot ? [ ]               # extra derivations copied onto /
, maxLayers ? 110
}:
let
  basePackages = with pkgs; [
    # core userland
    bashInteractive coreutils findutils gnugrep gnused gawk which less file
    procps psmisc util-linux shadow sudo curl wget openssl gnutar gzip xz bzip2
    iproute2 nano tzdata cacert glibcLocales glibc.bin
    # supervision
    s6 execline
    # session bus client side (de service wraps startwm in dbus-run-session)
    dbus
    # keyboard layouts (libxkbcommon reads these too, so this is NOT X11-only)
    xkeyboard_config
    # wayland userland. wtype here is the REAL one from nixpkgs (it speaks
    # virtual-keyboard-v1, which this image's scoot advertises via
    # [virtual_input]): the wtype-via-scoot shim of the Selkies image is
    # neither needed nor shipped. wlr-randr is absent on purpose: scoot
    # implements no output-management protocol for it to speak to.
    wl-clipboard wtype xdg-utils
    # graphics / fonts / themes
    mesa libGL libglvnd libva vulkan-loader
    fontconfig dejavu_fonts noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji
    hicolor-icon-theme adwaita-icon-theme gsettings-desktop-schemas glib dconf
    shared-mime-info
    # Present for application compatibility only (Chromium probes it): there
    # is NO audio daemon and NO audio transport in this image. RFB carries
    # no audio channel, so anything playing sound plays it into the void --
    # see the README's audio note.
    pulseaudio
  ]
  ++ extraPackages;

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

  etcFiles = runCommand "${name}-etc" { } ''
    mkdir -p $out/etc/{pam.d,fonts,ssl/certs,sudoers.d}

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
    PRETTY_NAME="Nix-built scoot VNC image"
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
    echo "scoot-vnc" > $out/etc/hostname
    cp ${fontsConf} $out/etc/fonts/fonts.conf
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-bundle.crt
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt
  '';

  # Filesystem skeleton: /usr -> nix env, /bin, /lib64 loaders, /defaults, /init, s6 services.
  skeleton = runCommand "${name}-skeleton" { } ''
    mkdir -p $out/usr $out/lib $out/lib64 $out/defaults $out/etc/s6 $out/usr/local/bin

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

    cp -r ${../rootfs/defaults}/. $out/defaults/
    cp ${startwm} $out/defaults/startwm.sh
    mkdir -p $out/defaults/config
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: d: "cp -r ${d} $out/defaults/config/${n}") configTemplates)}
    cp -r ${../rootfs/etc/s6-vnc}/. $out/etc/s6/
    cp ${../rootfs/init-vnc} $out/init
    chmod +x $out/init $out/defaults/*.sh
    find $out/etc/s6 -name run -exec chmod +x {} +

    # sudo must be a real setuid file, not a store symlink; perms set in fakeRootCommands.
    cp ${pkgs.sudo}/bin/sudo $out/usr/local/bin/sudo
  '';

  imageEnv = [
    "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    "HOME=/config"
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
    "GIO_EXTRA_MODULES=${pkgs.dconf.lib}/lib/gio/modules"
    "GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas"
    "LIBGL_ALWAYS_SOFTWARE=1"
    "TERMINAL=st"
    # VNC posture defaults (see the README's security note): unauthenticated
    # VNC on loopback only; noVNC's HTTP on all interfaces so a browser can
    # reach it. Override per container with -e.
    "VNC_LISTEN=127.0.0.1"
    "VNC_PORT=5900"
    "NOVNC_LISTEN=0.0.0.0"
    "NOVNC_PORT=6080"
    "VNC_FPS=30"
  ] ++ extraEnv;
in
dockerTools.buildLayeredImage {
  inherit name tag maxLayers;
  created = "now";

  contents = [ skeleton etcFiles ] ++ extraRoot;

  extraCommands = ''
    mkdir -p tmp config run/service var/log var/tmp var/cache
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
    ExposedPorts = { "5900/tcp" = { }; "6080/tcp" = { }; };
    Volumes = { "/config" = { }; };
    WorkingDir = "/config";
    Labels = {
      "org.opencontainers.image.title" = title;
      "org.opencontainers.image.description" = "Headless scoot over VNC (wayvnc) + noVNC, built with Nix";
      "org.opencontainers.image.source" = "https://github.com/yackey-labs/nixos-webtop";
    };
  };
}
