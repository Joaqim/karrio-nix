# IMPORTANT: This flake intentionally has ZERO inputs.
#
# nixpkgs is imported via npins (see nixpkgs.nix -> import ./npins), bypassing
# the flake input system entirely. This keeps `nix develop` fast and lets the
# same pins drive the plain `nix-shell`/direnv path (shell.nix) with no lock.

# DO NOT add flake inputs (nixpkgs, flake-parts, git-hooks, etc.).
# Instead, use npins or callPackage in the plain .nix files.
{
  description = "Generic karrio NixOS module, packages, and dev stack";

  outputs =
    { ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      eachSystem =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f (import ./nixpkgs.nix { inherit system; });
          }) systems
        );
    in
    {
      devShells = eachSystem (pkgs: {
        default = import ./dev-shell.nix {
          inherit pkgs;
        };
      });

      nixosModules.karrio = import ./modules/karrio.nix;
      nixosModules.default = import ./modules/karrio.nix;

      checks = eachSystem (pkgs: {
        karrio-module =
          let
            karrioPkgs = import ./nixpkgs.nix { inherit (pkgs.stdenv.hostPlatform) system; };
            serverPackage = karrioPkgs.callPackage ./pkgs/karrio-server.nix {
              src = import ./karrio-src.nix;
            };
            # Probe fed to `karrio shell` on stdin to assert the seeded system
            # carrier landed in the DB (SystemConnection is not exposed on any
            # unauthenticated endpoint). Kept as a file to sidestep nested-quote
            # fragility across the Nix/Python/shell layers.
            carrierProbe = pkgs.writeText "karrio-carrier-probe.py" ''
              import karrio.server.providers.models as providers
              exists = providers.SystemConnection.objects.filter(carrier_id="vm-generic").exists()
              print("CARRIER=" + str(exists))
              from karrio.server.manager.models import Address
              print("ADDR=" + str(Address.objects.filter(meta__label="VM Warehouse").exists()))
            '';
            # Django env for the ad-hoc carrier probe. These mirror the module's
            # serverEnv exactly for this node's option values (socket peer auth,
            # provisioned redis, the env-file SECRET_KEY). Kept static rather
            # than scraped from the running gunicorn's /proc/environ, whose
            # MainPID can point at a recycling worker and yield a partial read.
            # WORK_DIR / WORKER_DB_DIR are omitted so `karrio shell` does not
            # open the Huey sqlite worker store; LOG_DIR keeps loguru's file
            # sink on the writable state dir.
            probeEnv = pkgs.writeText "karrio-probe.env" ''
              DATABASE_ENGINE=postgresql
              DATABASE_HOST=/run/postgresql
              DATABASE_PORT=5432
              DATABASE_NAME=karrio
              DATABASE_USERNAME=karrio
              DATABASE_PASSWORD=
              REDIS_HOST=127.0.0.1
              REDIS_PORT=6379
              SECRET_KEY=vmtestsecret
              DEBUG_MODE=True
              LOG_DIR=/var/lib/karrio/log
            '';
          in
          karrioPkgs.testers.runNixOSTest {
            name = "karrio-module";
            nodes.machine =
              { ... }:
              {
                imports = [ ./modules/karrio.nix ];
                services.karrio.enable = true;
                services.karrio.mode = "development";
                # Declarative seed: assert the karrio-seed oneshot converges
                # branding (constance APP_NAME), a declared systemConfig key,
                # and a system carrier (SystemConnection upsert-by-carrierId).
                services.karrio.branding.appName = "VM Test Co";
                services.karrio.systemConfig.ORDER_DATA_RETENTION = 42;
                services.karrio.systemCarriers = [
                  {
                    carrierId = "vm-generic";
                    carrierCode = "generic";
                    testMode = true;
                  }
                ];
                services.karrio.addressBook = [
                  {
                    label = "VM Warehouse";
                    companyName = "VM Co";
                    addressLine1 = "1 Test St";
                    city = "London";
                    postalCode = "E1 6AN";
                    countryCode = "GB";
                    usage = [ "sender" ];
                  }
                ];
                services.karrio.environmentFiles = [
                  (pkgs.writeText "karrio.env" ''
                    SECRET_KEY=vmtestsecret
                    ADMIN_PASSWORD=vmtestadmin
                  '')
                ];
                services.karrio.dashboardEnvironmentFiles = [
                  (pkgs.writeText "karrio-dashboard.env" ''
                    NEXTAUTH_SECRET=vmtestnextauth
                  '')
                ];
                virtualisation.memorySize = 6144;
                virtualisation.diskSize = 8192;
              };
            testScript = ''
              machine.start()
              machine.wait_for_unit("karrio-migrate.service")
              # The declarative seed oneshot runs after migrate, before api.
              machine.wait_for_unit("karrio-seed.service")
              machine.wait_for_unit("karrio-api.service")
              machine.wait_until_succeeds("curl -sf http://127.0.0.1:5002/ -o /dev/null", timeout=180)

              # Declarative-seed convergence assertions.
              #
              # (a) Branding APP_NAME: the unauthenticated instance-metadata
              # endpoint (GET /) returns APP_NAME sourced from constance
              # (dataunits.contextual_metadata -> batch_get_constance_values),
              # so no Django env is needed — the seed converged iff the value
              # the module declared surfaces here.
              metadata = machine.succeed("curl -sf http://127.0.0.1:5002/")
              assert '"VM Test Co"' in metadata, (
                  "seed branding APP_NAME did not converge; GET / metadata was: " + metadata
              )

              # (b) System carrier: the SystemConnection upsert is not exposed
              # over an unauthenticated endpoint, so query the DB directly via
              # `karrio shell`, run as the karrio user with a static Django env
              # (probeEnv) that mirrors the module's serverEnv for this node.
              # The Python probe is fed on stdin to sidestep nested-quote
              # fragility; a writable CWD plus LOG_DIR keep karrio's loguru file
              # sink off the read-only store root.
              machine.succeed(
                  "install -o karrio -g karrio -m 0644 ${carrierProbe} /var/lib/karrio/carrier_probe.py"
              )
              carrier = machine.succeed(
                  "runuser -u karrio -- sh -c "
                  "'cd /var/lib/karrio && export HOME=/var/lib/karrio && "
                  "set -a && . ${probeEnv} && set +a && "
                  "${serverPackage}/bin/karrio shell < /var/lib/karrio/carrier_probe.py'"
              )
              assert "CARRIER=True" in carrier, (
                  "seed system carrier vm-generic SystemConnection not found; shell output: " + carrier
              )
              # (c) Address book: the declared addressBook entry is seeded as an
              # admin-owned Address row keyed by meta.label; the same `karrio
              # shell` probe asserts it exists (upsert-by-label convergence).
              assert "ADDR=True" in carrier, (
                  "seed address book entry 'VM Warehouse' Address not found; shell output: " + carrier
              )

              machine.wait_for_unit("karrio-dashboard.service")
              machine.wait_until_succeeds("curl -s http://127.0.0.1:3002/ -o /dev/null -w '%{http_code}' | grep -qE '200|307|302'", timeout=180)
              # strawberry-graphql version-drift probe: the schema must build and answer.
              machine.succeed("curl -sf http://127.0.0.1:5002/graphql -H 'content-type: application/json' -d '{\"query\":\"{ __typename }\"}' | grep -q __typename")
              # weasyprint/fontconfig smoke: the VM HTTP checks never exercise PDF
              # label/document rendering, which writes fontconfig and pango caches
              # under $HOME/.cache (HOME=/var/lib/karrio, the state dir). Render a
              # trivial PDF via the server python env to confirm the systemd
              # sandboxing (ProtectSystem=strict) does not block those cache writes.
              machine.succeed(
                  "runuser -u karrio -- env HOME=/var/lib/karrio "
                  "${serverPackage}/bin/karrio shell -c "
                  "\"import weasyprint; weasyprint.HTML(string='<h1>smoke</h1>').write_pdf('/var/lib/karrio/smoke.pdf')\""
              )
              machine.succeed("test -s /var/lib/karrio/smoke.pdf")
            '';
          };
      });

      apps = eachSystem (pkgs: {
        develop = {
          type = "app";
          program = "${pkgs.callPackage ./develop/develop.nix { }}/bin/karrio-develop";
        };
      });

      packages = eachSystem (pkgs: {
        karrio-server = pkgs.callPackage ./pkgs/karrio-server.nix {
          src = import ./karrio-src.nix;
        };
        karrio-dashboard = pkgs.callPackage ./pkgs/karrio-dashboard.nix {
          src = import ./karrio-src.nix;
        };
      });
    };
}
