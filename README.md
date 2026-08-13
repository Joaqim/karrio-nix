# karrio-nix
>
> [!WARNING]
> This project is almost wholly maintained and developed using LLM-assistance

A generic, zero-input Nix flake packaging [karrio](https://github.com/karrioapi/karrio) —
the open-source shipping platform — as a NixOS module, buildable packages, and a
live-source development stack.

The flake has no flake inputs: nixpkgs and the karrio source are pinned with
[npins](https://github.com/andir/npins) (see `nixpkgs.nix` and `karrio-src.nix`),
which keeps `nix develop` fast and lets the same pins drive the plain
`nix-shell`/direnv path via `shell.nix`.

## Outputs

- `nixosModules.karrio` (and `nixosModules.default`) — the `services.karrio`
  NixOS module: API (gunicorn), Huey worker, Next.js dashboard, and optional
  provisioned PostgreSQL and Redis.
- `overlays.default` — adds `karrio-server`, `karrio-dashboard`, and
  `karrioPython` (the interpreter carrying karrio's out-of-tree dependencies) to
  a consumer's nixpkgs, without replacing the top-level `python3`.
- `packages.<system>.karrio-server` — the karrio server derivation
  (`bin/karrio`, `bin/karrio-gunicorn`), built from the upstream pin.
- `packages.<system>.karrio-dashboard` — the standalone Next.js dashboard build.
- `devShells.<system>.default` — a Python environment carrying the SDK, CLI, and
  connector dependencies for editing karrio sources with no virtualenv step.
- `apps.<system>.develop` — `nix run .#develop` brings up the full live-source
  dev stack (postgres, redis, mailpit, API + worker, dashboard) under
  process-compose against a writable karrio checkout pointed to by `$KARRIO_ROOT`.
- `checks.<system>.karrio-module` — a NixOS VM test exercising the module end to
  end (migrate, API, dashboard, GraphQL, PDF rendering).

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

## Using the overlay

Applying `overlays.default` is the recommended way to consume the packages, and
it composes with the module: with the overlay in place the module builds against
your `pkgs.karrio-server`/`pkgs.karrio-dashboard`; without it the module falls
back to karrio-nix's own pinned build, so the overlay is recommended, not
required.

```nix
# In a NixOS configuration, given inputs.karrio-nix in the consuming flake:
{
  nixpkgs.overlays = [ inputs.karrio-nix.overlays.default ];
  imports = [ inputs.karrio-nix.nixosModules.karrio ];
}
```

The overlay adds `pkgs.karrio-server`, `pkgs.karrio-dashboard`, and
`pkgs.karrioPython` — the Python interpreter carrying karrio's out-of-tree
dependencies (Django 6 and the local derivations under `pkgs/`). It is
non-invasive: the top-level `pkgs.python3` is left untouched, so applying the
overlay does not rebuild the rest of your system's Python packages.

Building a karrio package directly follows the same source-override idiom as the
module, via the derivation's `src` argument:

```nix
pkgs.karrio-server.override { src = <their-karrio-src>; }
```

## Development

Point `KARRIO_ROOT` at a writable karrio checkout, then run the stack:

```shell
git clone https://github.com/karrioapi/karrio ./karrio
KARRIO_ROOT="$PWD/karrio" nix run .#develop
```
