# Selkies' python-xlib fork, repackaged out of the copy Selkies vendored.
#
# The Selkies commit this flake pins declares its dependency as
#
#     "python-xlib @ https://github.com/selkies-project/python-xlib/archive/master.zip"
#
# and that repository has since been DELETED -- the whole repo 404s, not just
# a revision -- which broke every image here, and linuxserver's own build with
# it (docker-baseimage-selkies pins the same Selkies commit and runs `pip
# install .` against the same dead URL).
#
# Upstream's answer was to vendor the fork into Selkies itself, at
# selkies-project/selkies@ed3249bd (2026-07-14), as src/selkies/Xlib. The
# revision taken here is that tree as of 2026-08-05, the same day as the
# Selkies commit `selkiesSrc` pins -- i.e. as close as this can get to the
# `master.zip` the pinned Selkies would have resolved at build time. Later
# revisions of the vendored tree carry work aimed at a much newer Selkies (a
# request-planning rewrite of protocol/rq.py in September) and are deliberately
# not taken.
#
# The fork rewrote every internal import to be relative and names neither
# `Xlib.` nor `selkies.` anywhere, so the tree is a drop-in top-level `Xlib`
# package and is published here under the distribution name python-xlib --
# which is what Selkies asks for, and what pynput resolves against.
#
# Stock python-xlib 0.33 from nixpkgs is NOT a substitute. The fork drops the
# `six` dependency and carries protocol changes Selkies relies on; the clearest
# is rq.Struct.pack_value returning `(binary, length, format)` rather than the
# bare binary, which is the path RandR MonitorInfo packing goes through -- and
# resizing the display to match the browser is the single most exercised X11
# code path in this image.
{ lib, buildPythonPackage, setuptools, fetchFromGitHub }:
buildPythonPackage {
  pname = "python-xlib-selkies";
  version = "0.33-unstable-2026-08-05";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "selkies-project";
    repo = "selkies";
    rev = "06ed8605d994a02d87a0e96b4bb77cc783affaf3";
    hash = "sha256-SqxagehS5ra7nJKyadPEwDoEi6ylDBpP54napqzWS0Y=";
  };

  # Only the vendored fork is wanted out of that checkout; the Selkies around
  # it is 750-odd commits newer than the one this flake builds, and leaving it
  # in place would also give setuptools a second top-level package to find.
  # The fork ships no packaging of its own -- it was vendored as a plain
  # directory -- so the pyproject.toml it needs is written here.
  # Only the vendored fork is wanted out of that checkout; the Selkies around
  # it is 750-odd commits newer than the one this flake builds, and leaving it
  # in place would also give setuptools a second top-level package to find.
  # The fork ships no packaging of its own -- it was vendored as a plain
  # directory -- so pyproject.toml comes from beside this file.
  postPatch = ''
    mv src/selkies/Xlib Xlib
    rm -rf src addons docs
    cp ${./python-xlib-selkies-pyproject.toml} pyproject.toml
  '';

  build-system = [ setuptools ];

  # Cheap proof the repackaging worked: `Xlib` has to import as a top-level
  # package, and the two extensions Selkies' input handler reaches for have to
  # come with it (that import is inside a try/except in input_handler.py, so a
  # half-packaged Xlib would not raise -- it would silently turn X11 input
  # injection off and leave a desktop nobody can type into).
  pythonImportsCheck = [ "Xlib" "Xlib.display" "Xlib.ext.xtest" "Xlib.ext.xfixes" ];

  # The fork carries no test suite of its own.
  doCheck = false;

  meta = {
    description = "Selkies' fork of python-xlib, taken from the copy vendored into Selkies";
    homepage = "https://github.com/selkies-project/selkies";
    license = lib.licenses.lgpl21Plus;
  };
}
