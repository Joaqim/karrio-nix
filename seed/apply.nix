{ writeText }:
writeText "karrio-seed-apply.py" ''
  # Shared idempotent seeder. Reads a JSON doc at $KARRIO_SEED_JSON and applies
  # it via the karrio management shell. { "_file": "/path" } values are read
  # from disk at runtime so secrets never live in the Nix store.
  import os, json

  def resolve(v):
      if isinstance(v, dict) and set(v.keys()) == {"_file"}:
          with open(v["_file"]) as fh:
              return fh.read().strip()
      return v

  seed = json.load(open(os.environ["KARRIO_SEED_JSON"]))

  # --- admin (seed-once) ---
  from django.contrib.auth import get_user_model
  U = get_user_model()
  admin_cfg = seed.get("admin")
  if admin_cfg and not U.objects.exists():
      U.objects.create_superuser(admin_cfg["email"], resolve(admin_cfg.get("password", "")) or None)
  admin = U.objects.order_by("id").first()

  # --- branding + system config (converge declared constance keys only) ---
  from constance import config
  import karrio.server.conf as conf
  allowed = set(conf.settings.CONSTANCE_CONFIG.keys())
  multitenant = bool(getattr(conf.settings, "MULTI_TENANTS", False) or getattr(conf.settings, "MULTI_TENANT_ENABLE", False))
  declared = {}
  declared.update(seed.get("branding", {}))     # APP_NAME / APP_WEBSITE
  declared.update(seed.get("systemConfig", {}))
  for k, v in declared.items():
      if k not in allowed:
          continue
      if multitenant and k in ("APP_NAME", "APP_WEBSITE"):
          continue
      setattr(config, k, resolve(v))

  # --- system carriers (upsert by carrier_id) ---
  # Lock-free upsert without update_or_create: get_or_create/update_or_create
  # wrap their lookup in select_for_update, and SystemConnection's manager
  # select_related("created_by", "rate_sheet") turns that into a FOR UPDATE
  # across a LEFT OUTER JOIN, which postgres rejects ("FOR UPDATE cannot be
  # applied to the nullable side of an outer join"). filter().first() + save()
  # is lock-free and portable.
  import karrio.server.providers.models as providers
  for c in seed.get("systemCarriers", []):
      creds = {}
      cf = c.get("credentialsFile")
      if cf and os.path.exists(cf):
          with open(cf) as fh:
              creds = json.load(fh)
      fields = dict(
          carrier_code=c["carrier_code"],
          test_mode=c.get("test_mode", True),
          active=c.get("active", True),
          credentials=creds,
          capabilities=c.get("capabilities", []),
          config=c.get("config", {}),
          created_by=admin,
      )
      conn = providers.SystemConnection.objects.filter(carrier_id=c["carrier_id"]).first()
      if conn is None:
          conn = providers.SystemConnection(carrier_id=c["carrier_id"], **fields)
      else:
          for key, value in fields.items():
              setattr(conn, key, value)
      conn.save()

  # --- address book (Address rows owned by the seeded admin; upsert by meta.label) ---
  addresses = seed.get("addressBook", [])
  if addresses and admin is not None:
      from karrio.server.manager.models import Address
      addr_fields = ("person_name", "company_name", "address_line1", "address_line2",
                     "city", "postal_code", "country_code", "state_code",
                     "phone_number", "email", "residential")
      for a in addresses:
          label = a["label"]
          fields = {k: a[k] for k in addr_fields if k in a and a[k] is not None}
          meta = {"label": label, "is_default": a.get("is_default", False), "usage": a.get("usage", [])}
          obj = Address.objects.filter(created_by=admin, meta__label=label).first()
          if obj is None:
              obj = Address(created_by=admin, meta=meta, **fields)
          else:
              for k, v in fields.items():
                  setattr(obj, k, v)
              obj.meta = {**(obj.meta or {}), **meta}
          obj.save()

  print("karrio seed applied")
''
