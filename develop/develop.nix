# `nix run .#develop` entrypoint: brings up the full live-source dev stack
# (postgres, redis, mailpit, the karrio API + huey worker running from a
# writable checkout, and the dashboard with hot reload) under process-compose.
#
# This is a LIVE-EDIT stack: it runs the karrio sources directly and writes into
# them (npm ci -> node_modules, next dev -> .next). It therefore requires a
# writable karrio checkout, located via $KARRIO_ROOT (see the entrypoint below).
# The upstream npins pin ((import ./npins).karrio) is a read-only store path and
# is intentionally NOT used as an automatic fallback here — it cannot host the
# npm/next writes. Point KARRIO_ROOT at your own `git clone` of karrioapi/karrio
# (or a fork) to develop.
#
# process-compose inherits this script's environment, so all runtime paths and
# karrio settings are exported here rather than baked statically into the
# config. This keeps the config store-path-only and lets the same config work
# regardless of where the checkout lives.
{
  writeShellApplication,
  callPackage,
  process-compose,
  git,
}:
let
  devEnv = callPackage ./dev-env.nix { };
  services = callPackage ./services.nix { };
  config = callPackage ./process-compose.nix { inherit devEnv services; };
in
writeShellApplication {
  name = "karrio-develop";
  runtimeInputs = [
    process-compose
    git
  ];
  text = ''
    repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

    # Live-edit stack: KARRIO_ROOT must be a WRITABLE karrio checkout (the stack
    # writes node_modules and .next into it). Honour an explicit KARRIO_ROOT;
    # otherwise fall back to a `karrio` checkout beside the repo. The upstream
    # npins pin is read-only and cannot host those writes, so it is not used as
    # an automatic fallback.
    export KARRIO_ROOT="''${KARRIO_ROOT:-$repo/karrio}"
    if [ ! -d "$KARRIO_ROOT/modules" ]; then
      echo "karrio-develop: KARRIO_ROOT ($KARRIO_ROOT) is not a karrio checkout." >&2
      echo "  Clone karrio and point KARRIO_ROOT at it, e.g.:" >&2
      echo "    git clone https://github.com/karrioapi/karrio \"$repo/karrio\"" >&2
      echo "    KARRIO_ROOT=$repo/karrio nix run .#develop" >&2
      exit 1
    fi
    export DEV_STATE="''${DEV_STATE:-$repo/.dev-state}"
    mkdir -p "$DEV_STATE"/{work,log,worker,static,redis,pg}

    export DATABASE_ENGINE=postgresql
    export DATABASE_HOST="$DEV_STATE"
    export DATABASE_PORT=5432
    export DATABASE_NAME=karrio
    export DATABASE_USERNAME=karrio
    export DATABASE_PASSWORD=""
    export REDIS_HOST=127.0.0.1
    export REDIS_PORT=6399

    export SECRET_KEY=dev
    export DEBUG_MODE=True
    export USE_HTTPS=False
    export ALLOW_SIGNUP=True
    export ENABLE_ALL_PLUGINS_BY_DEFAULT=True
    export KARRIO_HTTP_HOST=0.0.0.0
    export KARRIO_HTTP_PORT=5002
    export DETACHED_WORKER=True
    export ADMIN_EMAIL=admin@example.com

    export WORK_DIR="$DEV_STATE/work"
    export LOG_DIR="$DEV_STATE/log"
    export WORKER_DB_DIR="$DEV_STATE/worker"
    export STATIC_ROOT_DIR="$DEV_STATE/static"

    export NEXTAUTH_SECRET=dev
    export NEXTAUTH_URL=http://localhost:3002
    export AUTH_TRUST_HOST=true
    export KARRIO_URL=http://localhost:5002
    export NEXT_PUBLIC_KARRIO_PUBLIC_URL=http://localhost:5002
    export NEXT_PUBLIC_DASHBOARD_URL=http://localhost:3002
    export NEXT_TELEMETRY_DISABLED=1

    exec process-compose -f ${config} "$@"
  '';
}
