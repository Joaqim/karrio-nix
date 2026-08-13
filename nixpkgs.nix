# Pinned nixpkgs import — managed by npins.
# To update: npins update nixpkgs
let
  sources = import ./npins;
  nixpkgs = import sources.nixpkgs;
in
args:
nixpkgs (
  args
  // {
    overlays = (args.overlays or [ ]) ++ [
      (import ./overlay.nix)
      # Internal ergonomics only: bind THIS workspace's pkgs.python3 to the
      # karrio interpreter so dev-shell/develop/checks build against it without
      # threading it explicitly. overlays.default deliberately omits this so
      # external consumers stay non-invasive.
      (final: _: { python3 = final.karrioPython; })
    ];
  }
)
