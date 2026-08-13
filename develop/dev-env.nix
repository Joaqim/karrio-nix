{
  lib,
  python3,
  writeShellApplication,
  nodejs_22,
}:
let
  pythonEnv = python3.withPackages (import ../karrio-server-deps.nix);
  karrio = writeShellApplication {
    name = "karrio";
    runtimeInputs = [ pythonEnv ];
    text = ''
      root="''${KARRIO_ROOT:?KARRIO_ROOT must point at the ./karrio checkout}"
      extra="$root/apps/api:$root/modules/sdk:$root/modules/soap:$root/modules/cli"
      for d in "$root"/modules/core "$root"/modules/graph "$root"/modules/data \
               "$root"/modules/events "$root"/modules/manager "$root"/modules/orders \
               "$root"/modules/proxy "$root"/modules/pricing "$root"/modules/documents \
               "$root"/modules/admin; do
        extra="$d:$extra"
      done
      for d in "$root"/modules/connectors/*/ "$root"/plugins/*/; do
        [ -d "$d/karrio" ] && extra="$d:$extra"
      done
      export PYTHONPATH="$extra:''${PYTHONPATH:-}"
      export DJANGO_SETTINGS_MODULE=karrio.server.settings
      exec python3 -m karrio.server "$@"
    '';
  };
in
{
  inherit pythonEnv karrio;
  node = nodejs_22;
}
