# karrio-nix

A generic, zero-input Nix flake packaging [karrio](https://github.com/karrioapi/karrio) —
the open-source shipping platform — as a NixOS module, buildable packages, and a
live-source development stack.

The flake has no flake inputs: nixpkgs and the karrio source are pinned with
[npins](https://github.com/andir/npins) (see `nixpkgs.nix` and `karrio-src.nix`),
which keeps `nix develop` fast and lets the same pins drive the plain
`nix-shell`/direnv path via `shell.nix`.

## Outputs

- `nixosModules.karrio` (and `nixosModules.default`) — the `services.karrio`
  NixOS module: API (gunicorn), Huey worker, Next.js dashboard, optional
  provisioned PostgreSQL and Redis, and a declarative seeder for branding,
  system config, system carriers, and an address book.
- `packages.<system>.karrio-server` — the karrio server derivation
  (`bin/karrio`, `bin/karrio-gunicorn`), built from the upstream pin.
- `packages.<system>.karrio-dashboard` — the standalone Next.js dashboard build.
- `devShells.<system>.default` — a Python environment carrying the SDK, CLI, and
  connector dependencies for editing karrio sources with no virtualenv step.
- `apps.<system>.develop` — `nix run .#develop` brings up the full live-source
  dev stack (postgres, redis, mailpit, API + worker, dashboard) under
  process-compose against a writable karrio checkout pointed to by `$KARRIO_ROOT`.
- `checks.<system>.karrio-module` — a NixOS VM test exercising the module end to
  end (migrate, seed convergence, API, dashboard, GraphQL, PDF rendering).

## Using the module

Import `nixosModules.karrio` and enable the service:

```nix
services.karrio = {
  enable = true;
  environmentFiles = [ /run/secrets/karrio.env ];        # must supply SECRET_KEY
  dashboardEnvironmentFiles = [ /run/secrets/karrio-dashboard.env ];
};
```

The module defaults to the upstream karrio pin. Consumers who need a fork (for
finished carrier connectors or customizations upstream lacks) override the
source: `services.karrio.src = <their-fork-src>;`.

## Development

Point `KARRIO_ROOT` at a writable karrio checkout, then run the stack:

```shell
git clone https://github.com/karrioapi/karrio ./karrio
KARRIO_ROOT="$PWD/karrio" nix run .#develop
```
