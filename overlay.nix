_final: prev:
let
  python3 = prev.python3.override {
    self = python3;
    packageOverrides = import ./python-overlay.nix;
  };
in
{
  inherit python3;
}
