{ config, lib, pkgs, ... }:
let
  cfg = config.services.karrio;
  # Fallback pkgs from the workspace's OWN pinned nixpkgs + overlay, used when
  # the consumer has NOT applied overlays.default to their system pkgs. This
  # guarantees the Django 6 override and local derivations apply regardless of
  # the consumer's nixpkgs. When the overlay IS applied, the package options
  # below prefer the consumer's pkgs.karrio-* instead (see serverPackage).
  karrioPkgs = import ../nixpkgs.nix { inherit (pkgs.stdenv.hostPlatform) system; };

  # Authoritative "USE_HTTPS in effect" signal, honouring an extraSettings
  # override of the mode-derived default. When on, the API's Django
  # SECURE_SSL_REDIRECT answers any request lacking X-Forwarded-Proto: https
  # with a 301 to its https origin, so the dashboard's server-side calls must
  # reach the api through the proxy-fronted https endpoint (publicApiUrl)
  # rather than the plain-http loopback.
  useHttps = (cfg.extraSettings.USE_HTTPS or (if cfg.mode == "development" then "False" else "True")) == "True";
in
{
  options.services.karrio = {
    enable = lib.mkEnableOption "karrio native stack";

    mode = lib.mkOption {
      type = lib.types.enum [ "development" "production" ];
      default = "production";
      description = "Drives DEBUG_MODE/ALLOW_SIGNUP/USE_HTTPS, maildev, and the plugins default.";
    };

    src = lib.mkOption {
      type = lib.types.path;
      default = import ../karrio-src.nix;
      defaultText = lib.literalExpression "import ../karrio-src.nix";
      description = "karrio source (npins upstream pin by default; override to the fork or any checkout).";
    };

    serverPackage = lib.mkOption {
      type = lib.types.package;
      default = (pkgs.karrio-server or karrioPkgs.karrio-server).override { src = cfg.src; };
      defaultText = lib.literalExpression "(pkgs.karrio-server or karrioPkgs.karrio-server).override { inherit (cfg) src; }";
      description = "The karrio-server derivation (provides bin/karrio and bin/karrio-gunicorn). Prefers the consumer's overlay-provided pkgs.karrio-server, else the pinned build, with src re-threaded.";
    };

    dashboardPackage = lib.mkOption {
      type = lib.types.package;
      default = (pkgs.karrio-dashboard or karrioPkgs.karrio-dashboard).override { src = cfg.src; };
      defaultText = lib.literalExpression "(pkgs.karrio-dashboard or karrioPkgs.karrio-dashboard).override { inherit (cfg) src; }";
      description = "The karrio-dashboard derivation (provides bin/karrio-dashboard). Prefers the consumer's overlay-provided pkgs.karrio-dashboard, else the pinned build, with src re-threaded.";
    };

    host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Bind address for api and dashboard."; };
    apiPort = lib.mkOption { type = lib.types.port; default = 5002; };
    dashboardPort = lib.mkOption { type = lib.types.port; default = 3002; };

    publicApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${cfg.host}:${toString cfg.apiPort}";
      defaultText = lib.literalExpression ''"http://''${host}:''${apiPort}"'';
      description = "Public URL the browser uses to reach the api (NEXT_PUBLIC_KARRIO_PUBLIC_URL).";
    };
    publicDashboardUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${cfg.host}:${toString cfg.dashboardPort}";
      defaultText = lib.literalExpression ''"http://''${host}:''${dashboardPort}"'';
    };

    provisionPostgresql = lib.mkOption { type = lib.types.bool; default = true; };
    provisionRedis = lib.mkOption { type = lib.types.bool; default = true; };

    # External database note: with provisionPostgresql = false the module does
    # not create the role/database or configure authentication. The consumer
    # must set database.host and database.password to point at the external
    # server and ensure the database.user role and database.name database
    # already exist there. The socket peer-auth default (empty password against
    # /run/postgresql) applies only to the provisioned local postgres.
    database = {
      name = lib.mkOption { type = lib.types.str; default = "karrio"; };
      user = lib.mkOption { type = lib.types.str; default = "karrio"; };
      host = lib.mkOption { type = lib.types.str; default = "/run/postgresql"; description = "Default is the postgres unix socket dir (peer auth, no password)."; };
      port = lib.mkOption { type = lib.types.port; default = 5432; };
      password = lib.mkOption { type = lib.types.str; default = ""; description = "Empty for socket peer auth; set for TCP password auth."; };
    };

    redis = {
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port = lib.mkOption { type = lib.types.port; default = 6379; };
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "EnvironmentFile paths for the server units. Must supply SECRET_KEY (and ADMIN_PASSWORD to seed the superuser).";
    };
    dashboardEnvironmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "EnvironmentFile paths for the dashboard unit. Must supply NEXTAUTH_SECRET.";
    };

    adminEmail = lib.mkOption { type = lib.types.str; default = "admin@example.com"; };
    enableMaildev = lib.mkOption { type = lib.types.bool; default = cfg.mode == "development"; defaultText = lib.literalExpression ''mode == "development"''; };
    enableAllPlugins = lib.mkOption { type = lib.types.bool; default = cfg.mode == "development"; defaultText = lib.literalExpression ''mode == "development"''; };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra KEY=value env merged into the server environment.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.mode == "development" || cfg.environmentFiles != [ ];
          message = "services.karrio: production mode requires services.karrio.environmentFiles to supply SECRET_KEY (no insecure default).";
        }
        {
          assertion = !useHttps || lib.hasPrefix "https://" cfg.publicApiUrl;
          message = "services.karrio: USE_HTTPS is enabled but publicApiUrl (${cfg.publicApiUrl}) is not an https:// URL. The dashboard's server-side KARRIO_URL routes through publicApiUrl under https, which the api will 301-redirect to https; set publicApiUrl to the reverse-proxy-fronted https endpoint.";
        }
      ];

      users.users.karrio = { isSystemUser = true; group = "karrio"; home = "/var/lib/karrio"; };
      users.groups.karrio = { };

      services.postgresql = lib.mkIf cfg.provisionPostgresql {
        enable = true;
        ensureDatabases = [ cfg.database.name ];
        ensureUsers = [ { name = cfg.database.user; ensureDBOwnership = true; } ];
      };

      services.redis.servers.karrio = lib.mkIf cfg.provisionRedis {
        enable = true;
        bind = cfg.redis.host;
        port = cfg.redis.port;
      };
    }

    (
      let
        stateDir = "/var/lib/karrio";
        backendEnv = {
          DATABASE_ENGINE = "postgresql";
          DATABASE_HOST = cfg.database.host;
          DATABASE_PORT = toString cfg.database.port;
          DATABASE_NAME = cfg.database.name;
          DATABASE_USERNAME = cfg.database.user;
          DATABASE_PASSWORD = cfg.database.password;
          REDIS_HOST = cfg.redis.host;
          REDIS_PORT = toString cfg.redis.port;
        };
        serverEnv = backendEnv // {
          DEBUG_MODE = if cfg.mode == "development" then "True" else "False";
          USE_HTTPS = if useHttps then "True" else "False";
          ALLOW_SIGNUP = if cfg.mode == "development" then "True" else "False";
          ENABLE_ALL_PLUGINS_BY_DEFAULT = if cfg.enableAllPlugins then "True" else "False";
          KARRIO_HTTP_HOST = cfg.host;
          KARRIO_HTTP_PORT = toString cfg.apiPort;
          DETACHED_WORKER = "True";
          ADMIN_EMAIL = cfg.adminEmail;
          WORK_DIR = "${stateDir}/work";
          LOG_DIR = "${stateDir}/log";
          WORKER_DB_DIR = "${stateDir}/worker";
          STATIC_ROOT_DIR = "${stateDir}/static";
        } // cfg.extraSettings;

        # Systemd sandboxing shared by the karrio units. ProtectSystem=strict
        # makes the whole filesystem read-only except the StateDirectory, /dev,
        # /proc, /sys, and (with PrivateTmp) /tmp. All karrio writes go to the
        # state dir (WORK_DIR/LOG_DIR/WORKER_DB_DIR/STATIC_ROOT under
        # /var/lib/karrio, plus $HOME/.cache for fontconfig/weasyprint since
        # HOME=/var/lib/karrio). The postgres socket /run/postgresql and redis
        # TCP 127.0.0.1 stay reachable: no PrivateNetwork, no /run restriction.
        hardening = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
        };

        # Restart is intentionally not set here: karrio-migrate is Type=oneshot,
        # and systemd rejects Restart=always on oneshot units. The long-running
        # units (karrio-api, karrio-worker) set Restart individually.
        commonServer = {
          User = "karrio";
          Group = "karrio";
          StateDirectory = "karrio";
          EnvironmentFile = cfg.environmentFiles;
        } // hardening;
        pgUnits = lib.optional cfg.provisionPostgresql "postgresql.service";
        redisUnits = lib.optional cfg.provisionRedis "redis-karrio.service";
      in
      {
        systemd.services.karrio-migrate = {
          description = "karrio DB migrate + collectstatic + superuser seed";
          after = pgUnits ++ redisUnits;
          requires = pgUnits ++ redisUnits;
          before = [ "karrio-api.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv;
          restartTriggers = with cfg; [
            serverPackage
          ];
          # Type=oneshot defaults TimeoutStartSec to infinity; a hung migrate
          # (unreachable DB, blocked stdin) would stall the boot transaction
          # forever and starve every ordered-after unit (api, then dashboard)
          # of logs. Bound it so a hang fails visibly instead of hanging silently.
          serviceConfig = commonServer // { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 600; };
          script = ''
            ${cfg.serverPackage}/bin/karrio migrate --noinput
            ${cfg.serverPackage}/bin/karrio collectstatic --noinput
            ${cfg.serverPackage}/bin/karrio shell <<'PY'
            from django.contrib.auth import get_user_model
            import os
            U = get_user_model()
            if not U.objects.exists():
                U.objects.create_superuser(os.environ["ADMIN_EMAIL"], os.environ.get("ADMIN_PASSWORD", "demo"))
            PY
          '';
        };

        systemd.services.karrio-api = {
          description = "karrio API (gunicorn ASGI)";
          after = [ "karrio-migrate.service" ] ++ pgUnits ++ redisUnits;
          requires = [ "karrio-migrate.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv;
          restartTriggers = with cfg; [
            serverPackage
          ];
          serviceConfig = commonServer // {
            ExecStart = "${cfg.serverPackage}/bin/karrio-gunicorn";
            Restart = "always";
          };
        };

        systemd.services.karrio-worker = {
          description = "karrio Huey worker";
          after = [ "karrio-migrate.service" ] ++ redisUnits;
          requires = [ "karrio-migrate.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv;
          restartTriggers = with cfg; [
            serverPackage
          ];
          serviceConfig = commonServer // {
            ExecStart = "${cfg.serverPackage}/bin/karrio run_huey";
            Restart = "always";
          };
        };

        systemd.services.karrio-dashboard = {
          description = "karrio dashboard (Next.js standalone)";
          # No After=karrio-api: the dashboard reaches the api only at runtime
          # over HTTP (retryable until the api is up), so a hard ordering would
          # couple dashboard startup to the api/migrate boot chain and, if a
          # oneshot in that chain stalls, leave the dashboard queued with no
          # logs of its own.
          wantedBy = [ "multi-user.target" ];
          environment = {
            PORT = toString cfg.dashboardPort;
            HOSTNAME = cfg.host;
            AUTH_TRUST_HOST = "true";
            NEXTAUTH_URL = cfg.publicDashboardUrl;
            NEXT_CACHE_DIR = "%C/karrio-dashboard";
            # Server-side (NextAuth authorize()) reaches the api directly. When
            # the api enforces https it 301-redirects any request lacking
            # X-Forwarded-Proto: https, so this must be the proxy-fronted https
            # endpoint; only when https is off is the plain loopback safe. The
            # publicApiUrl-is-https assertion guards the misconfigured case.
            KARRIO_URL =
              if useHttps
              then cfg.publicApiUrl
              else "http://${cfg.host}:${toString cfg.apiPort}";
            NEXT_PUBLIC_KARRIO_PUBLIC_URL = cfg.publicApiUrl;
            NEXT_PUBLIC_DASHBOARD_URL = cfg.publicDashboardUrl;
          };
          restartTriggers = with cfg; [
            dashboardEnvironmentFiles
            dashboardPackage
            dashboardPort
            publicDashboardUrl
          ];
          serviceConfig = hardening // {
            User = "karrio";
            Group = "karrio";
            StateDirectory = "karrio-dashboard";
            WorkingDirectory = "/var/lib/karrio-dashboard";
            CacheDirectory = "karrio-dashboard";
            EnvironmentFile = cfg.dashboardEnvironmentFiles;
            Restart = "always";
            # Next.js standalone derives its prerender cache dir from the
            # server.js __dirname (const dir = path.join(__dirname); distDir
            # "./.next"), so the store is read-only, so run from a writable
            # working dir that symlinks the package's standalone tree but keeps
            # .next/cache writable.
            ExecStartPre = pkgs.writeShellScript "karrio-dashboard-prepare" ''
              set -eu
              root=${cfg.dashboardPackage}/share/karrio-dashboard
              dest=/var/lib/karrio-dashboard
              # cp -rs below copies the store's read-only dir modes (dr-xr-xr-x); as the
              # karrio user, rm needs writable dirs to unlink their entries on restart.
              if [ -d "$dest"/app ]; then find "$dest"/app -type d -exec chmod u+w {} +; fi
              rm -rf "$dest"/app; mkdir -p "$dest"/app/apps/dashboard/.next
              # symlink everything from the store tree, then shadow .next/cache with a writable dir
              cp -rs "$root"/. "$dest"/app/
              rm -rf "$dest"/app/apps/dashboard/.next/cache
              mkdir -p "$dest"/app/apps/dashboard/.next/cache
            '';
            # --preserve-symlinks-main keeps server.js's symlink path as its
            # __dirname. Without it Node realpaths the main module back to the
            # read-only store, so Next writes .next/cache into the store and
            # fails with ENOENT, defeating the writable-working-dir prep above.
            ExecStart = "${karrioPkgs.nodejs_22}/bin/node --preserve-symlinks-main /var/lib/karrio-dashboard/app/apps/dashboard/server.js";
          };
        };

        # Gate with mkIf on the definition rather than optionalAttrs on the
        # config attrset: forcing cfg.enableMaildev (whose default reads
        # cfg.mode) at the attrset-structure level recurses through config.
        systemd.services.karrio-maildev = lib.mkIf cfg.enableMaildev {
          description = "karrio dev SMTP catcher (mailpit)";
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [
            karrioPkgs.mailpit
          ];
          serviceConfig = {
            # maildev is absent from the pinned nixpkgs; mailpit provides the
            # equivalent dev SMTP catcher and is present.
            ExecStart = "${karrioPkgs.mailpit}/bin/mailpit";
            Restart = "always";
            DynamicUser = true;
          };
        };
      }
    )
  ]);
}
