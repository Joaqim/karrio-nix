{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  makeWrapper,
  src,
}:
let
  # karrio's documents module declares
  #   weasyprint.CSS(url="https://cdn.jsdelivr.net/npm/bulma@0.9.3/css/bulma.min.css")
  # as a module-level constant, so the URL is fetched over the network at Django
  # URL-conf import time by every management command and the API worker. Vendor
  # the stylesheet and rewrite the reference to a local file:// path so the
  # server needs no CDN egress at runtime (correct for air-gapped hosts and the
  # hermetic VM test alike).
  bulmaCss = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/bulma@0.9.3/css/bulma.min.css";
    sha256 = "1xkz2hyq84nxdp1zsxb5vjpw9w3d7xal2p6jk7bmfmd9g985nfsh";
  };
  pythonEnv = python3.withPackages (import ../karrio-server-deps.nix);

  # Source roots that extend the `karrio` pkgutil namespace, resolved from the
  # store copy of `src`. Mirrors ../dev-shell.nix but for a runtime package.
  # apps/api provides karrio.server.*; modules/* provide the rest.
  sourceRoots = [
    "apps/api"
    "modules/sdk"
    "modules/soap"
    "modules/cli"
    "modules/core"
    "modules/graph"
    "modules/data"
    "modules/events"
    "modules/manager"
    "modules/orders"
    "modules/proxy"
    "modules/pricing"
    "modules/documents"
    "modules/admin"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "karrio-server";
  version = "unstable";
  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # Rewrite the CDN stylesheet reference to the vendored local copy before the
    # source tree is copied into the store. --replace-fail makes the build error
    # loudly if the upstream string ever changes.
    substituteInPlace modules/documents/karrio/server/documents/generator.py \
      --replace-fail \
        'weasyprint.CSS(url="https://cdn.jsdelivr.net/npm/bulma@0.9.3/css/bulma.min.css")' \
        'weasyprint.CSS(url="file://${bulmaCss}")'

    mkdir -p $out/share/karrio
    cp -r . $out/share/karrio/src

    pythonpath=""
    for r in ${lib.concatStringsSep " " sourceRoots}; do
      pythonpath="$out/share/karrio/src/$r:$pythonpath"
    done
    # Connectors and plugins extend the namespace too.
    for d in $out/share/karrio/src/modules/connectors/*/ $out/share/karrio/src/plugins/*/; do
      [ -d "$d/karrio" ] && pythonpath="$d:$pythonpath"
    done

    # Strip the trailing separator left by the accumulator loops above; a
    # trailing colon makes Python treat CWD as an import path, which is unsafe
    # for a server process.
    pythonpath="''${pythonpath%:}"

    mkdir -p $out/bin
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/karrio \
      --set PYTHONPATH "$pythonpath" \
      --set DJANGO_SETTINGS_MODULE karrio.server.settings \
      --add-flags "-m karrio.server"

    makeWrapper ${pythonEnv}/bin/gunicorn $out/bin/karrio-gunicorn \
      --set PYTHONPATH "$pythonpath" \
      --set DJANGO_SETTINGS_MODULE karrio.server.settings \
      --add-flags "--config $out/share/karrio/src/apps/api/gunicorn-cfg.py" \
      --add-flags "karrio.server.asgi" \
      --add-flags "-k karrio.server.workers.UvicornWorker"

    runHook postInstall
  '';

  meta = {
    description = "karrio Django server (API + management CLI) as a native Nix package";
    mainProgram = "karrio";
  };
}
