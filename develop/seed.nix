# Dev seed document consumed by the shared declarative seeder (seed/apply.nix).
# Emits neutral branding (APP_NAME) only; no carriers or address book. The
# admin superuser is seeded separately as a guarded inline step in the
# process-compose migrate-seed process (using KARRIO_DEV_ADMIN_PASSWORD), so it
# is intentionally absent here; apply.py tolerates a missing "admin" key.
#
# Consumers pinning their own carriers should set services.karrio.systemCarriers
# in their NixOS module configuration rather than editing this dev seed.
{ callPackage }:
callPackage ../seed/mk-seed-json.nix { } {
  branding = { APP_NAME = "Karrio Dev"; };
}
