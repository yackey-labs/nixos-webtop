# nginx with the fancyindex module (used for the /files download browser).
{ nginx, nginxModules }:
nginx.override { modules = [ nginxModules.fancyindex ]; }
