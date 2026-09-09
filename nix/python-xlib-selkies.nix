# Selkies depends on its own python-xlib fork (extra XFixes/XTest bits).
{ xlib, fetchFromGitHub }:
xlib.overridePythonAttrs (old: {
  pname = "python-xlib-selkies";
  version = "0.33-unstable-2026-02-13";
  src = fetchFromGitHub {
    owner = "selkies-project";
    repo = "python-xlib";
    rev = "932e5d18c3edcb6a02e11c5e0b31c0f0ce4fd571";
    hash = "sha256-6Fl8qcxvbPlMfRs1yxQbGPc3Mh0XibsaAEOuKewrUJ4=";
  };
  env = (old.env or { }) // { SETUPTOOLS_SCM_PRETEND_VERSION = "0.33"; };
  doCheck = false;
})
