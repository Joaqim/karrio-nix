# Default karrio source, pinned upstream (karrioapi/karrio) via npins.
# The module and derivations accept a `src` override; this is the generic
# default that defines the minimally viable deployment.
let
  sources = import ./npins;
in
sources.karrio
