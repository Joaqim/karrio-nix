{ writeText }:
seed: writeText "karrio-seed.json" (builtins.toJSON seed)
