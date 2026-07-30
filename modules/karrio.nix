{ config, lib, pkgs, ... }:
let
  cfg = config.services.karrio;
  # Build default packages from the workspace's OWN pinned nixpkgs + overlay,
  # not the consuming system's pkgs — the Django 6 override and local
  # derivations must apply. Match the host system.
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
      default = karrioPkgs.callPackage ../pkgs/karrio-server.nix { src = cfg.src; };
      defaultText = lib.literalExpression "<karrio-server built from src>";
      description = "The karrio-server derivation (provides bin/karrio and bin/karrio-gunicorn).";
    };

    dashboardPackage = lib.mkOption {
      type = lib.types.package;
      default = karrioPkgs.callPackage ../pkgs/karrio-dashboard.nix { src = cfg.src; };
      defaultText = lib.literalExpression "<karrio-dashboard built from src>";
      description = "The karrio-dashboard derivation (provides bin/karrio-dashboard).";
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

    branding = {
      appName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "constance APP_NAME (converged each activation).";
      };
      appWebsite = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "constance APP_WEBSITE.";
      };
    };

    systemConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [
        lib.types.str
        lib.types.int
        lib.types.bool
        (lib.types.attrsOf lib.types.str)
      ]);
      default = { };
      description = ''
        Declared constance keys to converge. A value of { _file = "/path"; } is
        read at runtime (secrets). Only declared keys are touched.
      '';
    };

    systemCarriers = lib.mkOption {
      default = [ ];
      description = "System carrier connections upserted by carrierId.";
      type = lib.types.listOf (lib.types.submodule ({ ... }: {
        options = {
          carrierId = lib.mkOption { type = lib.types.str; };
          carrierCode = lib.mkOption { type = lib.types.str; };
          testMode = lib.mkOption { type = lib.types.bool; default = true; };
          active = lib.mkOption { type = lib.types.bool; default = true; };
          capabilities = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "rating" "shipping" "tracking" ];
          };
          credentialsFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
          config = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
        };
      }));
    };

    addressBook = lib.mkOption {
      default = [ ];
      description = "Address book entries seeded as Address rows owned by the admin, upserted by label.";
      type = lib.types.listOf (lib.types.submodule ({ ... }: {
        options = {
          label = lib.mkOption { type = lib.types.str; description = "meta.label — the stable upsert key."; };
          usage = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "meta.usage role tags (sender/pickup/return/...)."; };
          isDefault = lib.mkOption { type = lib.types.bool; default = false; };
          companyName = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          personName = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          addressLine1 = lib.mkOption { type = lib.types.str; };
          addressLine2 = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          city = lib.mkOption { type = lib.types.str; };
          postalCode = lib.mkOption { type = lib.types.str; };
          countryCode = lib.mkOption { type = lib.types.str; description = "ISO country code (required by karrio)."; };
          stateCode = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          phoneNumber = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          email = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          residential = lib.mkOption { type = lib.types.bool; default = false; };
        };
      }));
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

        # Normalize the friendly Nix option names to the karrio-native JSON keys
        # (APP_NAME/APP_WEBSITE/carrier_id/carrier_code/...) that apply.py reads.
        seedDoc =
          (lib.optionalAttrs (cfg.branding.appName != null || cfg.branding.appWebsite != null) {
            branding = lib.filterAttrs (_: v: v != null) {
              APP_NAME = cfg.branding.appName;
              APP_WEBSITE = cfg.branding.appWebsite;
            };
          })
          // (lib.optionalAttrs (cfg.systemConfig != { }) { systemConfig = cfg.systemConfig; })
          // (lib.optionalAttrs (cfg.systemCarriers != [ ]) {
            systemCarriers = map (c: {
              carrier_id = c.carrierId;
              carrier_code = c.carrierCode;
              test_mode = c.testMode;
              active = c.active;
              capabilities = c.capabilities;
              config = c.config;
            } // lib.optionalAttrs (c.credentialsFile != null) { credentialsFile = toString c.credentialsFile; }) cfg.systemCarriers;
          })
          // (lib.optionalAttrs (cfg.addressBook != [ ]) {
            addressBook = map (a: lib.filterAttrs (_: v: v != null) {
              label = a.label;
              usage = a.usage;
              is_default = a.isDefault;
              company_name = a.companyName;
              person_name = a.personName;
              address_line1 = a.addressLine1;
              address_line2 = a.addressLine2;
              city = a.city;
              postal_code = a.postalCode;
              country_code = a.countryCode;
              state_code = a.stateCode;
              phone_number = a.phoneNumber;
              email = a.email;
              residential = a.residential;
            }) cfg.addressBook;
          });
        seedJson = karrioPkgs.callPackage ../seed/mk-seed-json.nix { } seedDoc;
        seedApply = karrioPkgs.callPackage ../seed/apply.nix { };
      in
      {
        systemd.services.karrio-migrate = {
          description = "karrio DB migrate + collectstatic + superuser seed";
          after = pgUnits ++ redisUnits;
          requires = pgUnits ++ redisUnits;
          before = [ "karrio-api.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv;
          serviceConfig = commonServer // { Type = "oneshot"; RemainAfterExit = true; };
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

        systemd.services.karrio-seed = lib.mkIf (seedDoc != { }) {
          description = "karrio declarative system seed (branding, config, carriers)";
          after = [ "karrio-migrate.service" ];
          requires = [ "karrio-migrate.service" ];
          before = [ "karrio-api.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv // { KARRIO_SEED_JSON = "${seedJson}"; };
          serviceConfig = commonServer // hardening // { Type = "oneshot"; RemainAfterExit = true; };
          script = "${cfg.serverPackage}/bin/karrio shell < ${seedApply}";
        };

        systemd.services.karrio-api = {
          description = "karrio API (gunicorn ASGI)";
          after = [ "karrio-migrate.service" ]
            ++ lib.optional (seedDoc != { }) "karrio-seed.service"
            ++ pgUnits ++ redisUnits;
          requires = [ "karrio-migrate.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = serverEnv;
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
          serviceConfig = commonServer // {
            ExecStart = "${cfg.serverPackage}/bin/karrio run_huey";
            Restart = "always";
          };
        };

        systemd.services.karrio-dashboard = {
          description = "karrio dashboard (Next.js standalone)";
          after = [ "karrio-api.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            PORT = toString cfg.dashboardPort;
            HOSTNAME = cfg.host;
            AUTH_TRUST_HOST = "true";
            NEXTAUTH_URL = cfg.publicDashboardUrl;
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
          serviceConfig = hardening // {
            User = "karrio";
            Group = "karrio";
            StateDirectory = "karrio-dashboard";
            WorkingDirectory = "/var/lib/karrio-dashboard";
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
