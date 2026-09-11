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
            serverPackage = karrioPkgs.karrio-server;
          in
          karrioPkgs.testers.runNixOSTest {
            name = "karrio-module";
            nodes.machine =
              { ... }:
              {
                imports = [ ./modules/karrio.nix ];
                services.karrio.enable = true;
                services.karrio.mode = "development";
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
              machine.wait_for_unit("karrio-api.service")
              machine.wait_until_succeeds("curl -sf http://127.0.0.1:5002/ -o /dev/null", timeout=180)

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

      overlays.default = import ./overlay.nix;

      packages = eachSystem (pkgs: {
        inherit (pkgs) karrio-server karrio-dashboard karrio-sdk;
      });
    };
}
