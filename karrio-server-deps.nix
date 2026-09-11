# Server-side Python dependency closure, shared by the production derivation
# (pkgs/karrio-server.nix) and the local dev stack (develop/dev-env.nix)
# so dev and prod resolve the identical set.
#
# Third-party runtime deps. Stock nixpkgs where possible; packages absent
# from the pin or needing a different version are supplied by the overlay
# (python-overlay.nix).
ps: [
  # Django stack (karrio targets Django 6)
  ps.django_6
  ps.djangorestframework
  ps.djangorestframework-simplejwt
  ps.django-constance
  ps.django-cors-headers
  ps.django-filter
  ps.django-oauth-toolkit
  ps.django-otp
  ps.django-two-factor-auth
  ps.django-redis
  ps.django-picklefield
  ps.django-health-check
  ps.jsonfield
  ps.django-import-export
  ps.django-phonenumber-field
  ps.django-formtools
  ps.drf-spectacular
  ps.django-downloadview
  ps.django-email-verification
  ps.drf-api-tracking
  # Server runtime
  ps.gunicorn
  ps.uvicorn
  ps.h11
  ps.whitenoise
  ps.huey
  ps.redis
  ps.hiredis
  ps.psycopg2
  ps.dj-database-url
  ps.python-decouple
  ps.strawberry-graphql
  ps.graphql-core
  ps.sentry-sdk
  ps.loguru
  ps.posthog
  # Documents / labels
  ps.weasyprint
  ps.python-barcode
  ps.qrcode
  ps.pillow
  ps.pypdf
  ps.lxml
  ps.cffi
  ps.pyzint
  # SDK deps needed at runtime
  ps.attrs
  ps.jstruct
  ps.xmltodict
  ps.phonenumbers
  ps.toml
  ps.pyyaml
  ps.jinja2
  ps.dnspython
  ps.psutil
  ps.openpyxl
  ps.six
]
