# Development shell for `nix-shell` / direnv (`use nix`).
# Pinned via npins (see ./nixpkgs.nix); no flake required. Avoids copying the
# working tree into the store, which the flake path incurs.
{
  pkgs ? import ./nixpkgs.nix { },
}:
import ./dev-shell.nix { inherit pkgs; }
