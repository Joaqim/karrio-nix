# The one karrio overlay, exported as `overlays.default` and base-injected by
# nixpkgs.nix. Non-invasive: it exposes the karrio interpreter as a dedicated
# `karrioPython` attribute and builds the packages against it explicitly, so a
# consumer's top-level `pkgs.python3` is left untouched (no system-wide rebuild,
# no recursion). Applying this one overlay is all a consumer needs to get
# `karrio-server`/`karrio-dashboard` built with the Django 6 + out-of-tree deps.
final: prev:
let
  # Interpreter carrying dependencies outside nixpkgs (see python-overlay.nix).
  # Built from prev.python3, so rebinding final.python3 elsewhere cannot recurse.
  karrioPython = prev.python3.override {
    self = karrioPython;
    packageOverrides = import ./python-overlay.nix;
  };
in
{
  inherit karrioPython;

  karrio-server = final.callPackage ./pkgs/karrio-server.nix {
    src = import ./karrio-src.nix;
    python3 = karrioPython;
  };

  karrio-dashboard = final.callPackage ./pkgs/karrio-dashboard.nix {
    src = import ./karrio-src.nix;
  };
}
