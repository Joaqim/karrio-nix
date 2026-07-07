{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_22,
  src,
  npmDepsHash ? "sha256-zuSV3W2JSkrU0WbGCpfTaLYOs85dj9f3yevYQnlEykE=",
  # ee workspace members that the root `package-lock.json` references via
  # `link: true` node_modules entries. The upstream pin ships their real
  # package.json files, but those declare private Enterprise-only dependencies
  # that are not in the resolvable closure. Overwriting each with a minimal
  # placeholder lets `npm ci` resolve the workspace without the private deps;
  # the dashboard imports none of these (its @karrio/* closure is under
  # packages/*). Derived in Task 1 Step 1 from the src lockfile: the only
  # `link: true` targets under ee/ are ee/packages/console and
  # ee/apps/platform. The ee/insiders/packages/elements lockfile entry is
  # marked extraneous with no link target, so it needs no stub.
  eeStubs ? [
    {
      path = "ee/packages/console";
      name = "@karrio/console";
    }
    {
      path = "ee/apps/platform";
      name = "@karrio/platform";
    }
  ],
}:
buildNpmPackage {
  pname = "karrio-dashboard";
  version = "unstable";
  inherit src;

  nodejs = nodejs_22;

  nativeBuildInputs = [ makeWrapper ];

  # Inject a placeholder package.json for each ee workspace member so the root
  # workspace resolves without the private Enterprise dependency closure.
  postPatch = lib.concatMapStringsSep "\n" (s: ''
    mkdir -p ${lib.escapeShellArg s.path}
    printf '%s\n' '{ "name": "${s.name}", "version": "0.0.0", "private": true }' \
      > ${lib.escapeShellArg s.path}/package.json
  '') eeStubs;

  inherit npmDepsHash;

  NEXT_TELEMETRY_DISABLED = "1";

  # Build only the dashboard workspace (a full monorepo build would compile
  # unrelated apps). No Sentry auth token is set, so the build stays offline.
  buildPhase = ''
    runHook preBuild
    npm run build -w apps/dashboard
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/karrio-dashboard
    cp -r apps/dashboard/.next/standalone/. $out/share/karrio-dashboard/
    mkdir -p $out/share/karrio-dashboard/apps/dashboard/.next
    cp -r apps/dashboard/.next/static $out/share/karrio-dashboard/apps/dashboard/.next/static
    cp -r apps/dashboard/public $out/share/karrio-dashboard/apps/dashboard/public
    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/karrio-dashboard \
      --add-flags "$out/share/karrio-dashboard/apps/dashboard/server.js"
    runHook postInstall
  '';

  meta = {
    description = "karrio Next.js dashboard (standalone build) as a native Nix package";
    mainProgram = "karrio-dashboard";
  };
}
