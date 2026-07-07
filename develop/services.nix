{ lib, writeShellApplication, postgresql_16, redis, mailpit }:
let
  # Every launcher roots its state under DEV_STATE (default $PWD/.dev-state), so
  # the whole dev stack is disposable: delete the directory and it is gone.
  devStatePrelude = ''
    DEV_STATE="''${DEV_STATE:-$PWD/.dev-state}"
    mkdir -p "$DEV_STATE"
  '';
in
{
  # Ephemeral postgres. Trust auth over a unix socket in $DEV_STATE means
  # consumers set DATABASE_HOST=$DEV_STATE with no password. The karrio role and
  # database are created once, during the first-init branch, by briefly starting
  # postgres before the long-running exec.
  pg = writeShellApplication {
    name = "karrio-dev-pg";
    runtimeInputs = [ postgresql_16 ];
    text = ''
      ${devStatePrelude}
      pgdata="$DEV_STATE/pg"

      if [ ! -f "$pgdata/PG_VERSION" ]; then
        initdb -D "$pgdata" --auth=trust --no-locale --encoding=UTF8
        pg_ctl -D "$pgdata" -o "-k \"$DEV_STATE\" -c listen_addresses=127.0.0.1 -p 5432" -w start
        createuser -h "$DEV_STATE" -p 5432 --superuser karrio
        createdb -h "$DEV_STATE" -p 5432 --owner=karrio karrio
        pg_ctl -D "$pgdata" -m fast -w stop
      fi

      exec postgres -D "$pgdata" -k "$DEV_STATE" -c listen_addresses=127.0.0.1 -p 5432
    '';
  };

  redis = writeShellApplication {
    name = "karrio-dev-redis";
    runtimeInputs = [ redis ];
    text = ''
      ${devStatePrelude}
      mkdir -p "$DEV_STATE/redis"
      # Bind a non-default port (6379 -> 6399) so a developer's host Redis on the
      # default port cannot be silently shared by (or collide with) this stack.
      exec redis-server \
        --port 6399 \
        --bind 127.0.0.1 \
        --dir "$DEV_STATE/redis" \
        --save "" \
        --appendonly no
    '';
  };

  mailpit = writeShellApplication {
    name = "karrio-dev-mailpit";
    runtimeInputs = [ mailpit ];
    text = ''
      ${devStatePrelude}
      exec mailpit \
        --db-file "$DEV_STATE/mailpit.db" \
        --smtp 127.0.0.1:1025 \
        --listen 127.0.0.1:8025
    '';
  };
}
