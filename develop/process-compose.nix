# Serializes the dev-stack process graph into a process-compose config file.
# JSON is valid YAML, and process-compose reads the .yaml by content, so the
# attrset below is emitted with builtins.toJSON. Runtime paths (KARRIO_ROOT,
# DEV_STATE and the karrio env) are exported by the develop.nix entrypoint and
# inherited by every process; only store paths are baked in here.
{
  writeText,
  devEnv,
  services,
  postgresql_16,
  redis,
  seed,
  seedApply,
}:
let
  # Guarded dev admin seed, kept as its own script so the migrate-seed command
  # stays a single-line `&&` chain: process-compose does not evaluate the
  # command under a full shell, so embedded heredocs and `\` line continuations
  # are unsafe. Piping a store-path script via `karrio shell < ...` is.
  adminSeed = writeText "karrio-dev-admin-seed.py" ''
    import os
    from django.contrib.auth import get_user_model

    U = get_user_model()
    if not U.objects.exists():
        U.objects.create_superuser(
            "admin@example.com",
            os.environ.get("KARRIO_DEV_ADMIN_PASSWORD", "karriodev"),
        )
  '';
in
writeText "process-compose.yaml" (builtins.toJSON {
  version = "0.5";
  processes = {
    postgres = {
      command = "${services.pg}/bin/karrio-dev-pg";
      readiness_probe.exec.command = ''${postgresql_16}/bin/pg_isready -h "$DEV_STATE" -p 5432'';
      availability.restart = "on_failure";
    };

    redis = {
      command = "${services.redis}/bin/karrio-dev-redis";
      readiness_probe.exec.command = "${redis}/bin/redis-cli -p 6399 ping";
      availability.restart = "on_failure";
    };

    mailpit = {
      command = "${services.mailpit}/bin/karrio-dev-mailpit";
      availability.restart = "on_failure";
    };

    npm-ci = {
      # Idempotent: npm's lockfile marker is written only on a complete install,
      # so its presence means node_modules is already populated.
      command = ''[ -e "$KARRIO_ROOT/node_modules/.package-lock.json" ] || (cd "$KARRIO_ROOT" && ${devEnv.node}/bin/npm ci)'';
      availability.restart = "no";
    };

    migrate-seed = {
      # migrate + collectstatic, then seed the dev admin (guarded, using
      # KARRIO_DEV_ADMIN_PASSWORD), then converge branding + carriers via the
      # shared declarative seeder (nix/seed/apply.nix) with the dev seed JSON.
      command = "${devEnv.karrio}/bin/karrio migrate --noinput && ${devEnv.karrio}/bin/karrio collectstatic --noinput && ${devEnv.karrio}/bin/karrio shell < ${adminSeed} && KARRIO_SEED_JSON=${seed} ${devEnv.karrio}/bin/karrio shell < ${seedApply}";
      depends_on = {
        postgres.condition = "process_healthy";
        redis.condition = "process_healthy";
      };
      availability.restart = "no";
    };

    api = {
      command = "${devEnv.karrio}/bin/karrio runserver 0.0.0.0:5002";
      depends_on.migrate-seed.condition = "process_completed_successfully";
    };

    worker = {
      command = "${devEnv.karrio}/bin/karrio run_huey";
      depends_on.migrate-seed.condition = "process_completed_successfully";
    };

    dashboard = {
      command = ''cd "$KARRIO_ROOT" && ${devEnv.node}/bin/npm run dev -w apps/dashboard'';
      depends_on = {
        api.condition = "process_started";
        npm-ci.condition = "process_completed_successfully";
      };
    };
  };
})
