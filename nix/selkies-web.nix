# Frontend: selkies-web-core + the two dashboards, built the way linuxserver's
# Dockerfile does it, but reproducibly (vendored lockfiles in ../frontend/locks).
{ lib, stdenv, buildNpmPackage, fetchurl, selkiesSrc }:
let
  # SDL_GameControllerDB snapshot; gendb.js normally fetches this at build time.
  gamecontrollerdb = fetchurl {
    url = "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/28a856f2b92da8891b161acd0abd64fbf4445d97/gamecontrollerdb.txt";
    hash = "sha256-9suSUsPDeQw1E8fSeeW0s3sNddc59qVz86VUcZFPveY=";
  };
  webtopIcon = fetchurl {
    url = "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png";
    hash = "sha256-wOeSC/8OepNkwC5e8PRy3SbXyf3nFP/hZI7zj/8oqpM=";
  };
  favicon = fetchurl {
    url = "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/selkies-icon.ico";
    hash = "sha256-qiCauHWzcDhLAsKWjQNVRInJ7whuWryVl92g1jBS/os=";
  };

  # Prebuilt binaries from npm may carry a non-Nix ELF interpreter (static
  # builds, like esbuild on some platforms, are left alone).
  patchNpmBinaries = ''
    interp="$(cat "$NIX_CC/nix-support/dynamic-linker")"
    find node_modules -path '*/@esbuild/*/bin/esbuild' -type f | while read -r f; do
      patchelf --set-interpreter "$interp" "$f" 2>/dev/null || true
    done
  '';

  core = buildNpmPackage {
    pname = "selkies-web-core";
    version = "1.0.0";
    src = selkiesSrc;
    sourceRoot = "${selkiesSrc.name}/addons/selkies-web-core";
    npmDepsHash = "sha256-HTpkmPdTJHPssWsYTNkGTAXUZaEwA/jIO8pU8eE1msQ=";
    npmRebuildFlags = [ "--ignore-scripts" ];
    postPatch = ''
      cp ${../frontend/locks/selkies-web-core.package-lock.json} package-lock.json
      substituteInPlace gendb.js --replace-fail \
        "const response = await fetch(DB_URL);" \
        "const response = { ok: true, text: async () => fs.readFileSync(process.env.SELKIES_GCDB, 'utf8') };"
    '';
    env.SELKIES_GCDB = gamecontrollerdb;
    preBuild = patchNpmBinaries;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/. $out/
      cp -r nginx $out/nginx
      runHook postInstall
    '';
  };

  mkDashboard = name: npmDepsHash: buildNpmPackage {
    pname = name;
    version = "0.0.1";
    src = selkiesSrc;
    sourceRoot = "${selkiesSrc.name}/addons/${name}";
    inherit npmDepsHash;
    npmRebuildFlags = [ "--ignore-scripts" ];
    postPatch = ''
      cp ${../frontend/locks + "/${name}.package-lock.json"} package-lock.json
      cp ${core}/selkies-core.js src/
    '';
    preBuild = patchNpmBinaries;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/src $out/nginx
      cp -r dist/. $out/
      cp ${core}/selkies-core.js $out/src/
      cp ${selkiesSrc}/addons/universal-touch-gamepad/universalTouchGamepad.js $out/src/
      cp ${core}/nginx/* $out/nginx/
      cp -r ${core}/jsdb $out/jsdb
      runHook postInstall
    '';
  };

  dashboard = mkDashboard "selkies-dashboard" "sha256-DsR/OLYwq4pupGDwKyFeMQWXAdAcc61Vjpabr92ebB8=";
  dashboardWish = mkDashboard "selkies-dashboard-wish" "sha256-eNhHhQa7JMh6/6BvezDotQaz+MUtcXsR6R3NTa9ozQo=";
in
stdenv.mkDerivation {
  pname = "selkies-web";
  version = "1.0.0";
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/share/selkies/www
    cp -r ${dashboard} $out/share/selkies/selkies-dashboard
    cp -r ${dashboardWish} $out/share/selkies/selkies-dashboard-wish
    cp ${webtopIcon} $out/share/selkies/www/icon.png
    cp ${favicon} $out/share/selkies/www/favicon.ico
  '';
  passthru = { inherit core dashboard dashboardWish; };
}
