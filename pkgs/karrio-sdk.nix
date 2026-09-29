{
  lib,
  src,
  python3Packages,
  jstruct,
  py-soap,
  lxml-stubs,
  ...
}:
let
  projectVersion = dir: (lib.importTOML "${dir}/pyproject.toml").project.version;

  sdkSrc = "${src}/modules/sdk";
  connectorsDir = "${src}/modules/connectors";

  # Upstream karrio still imports PyPDF2 at module load; forks that moved to
  # pypdf drop it from pyproject, so follow whichever the src declares.
  requiresPyPDF2 = lib.any (
    dep: lib.hasPrefix "pypdf2" (lib.toLower dep)
  ) (lib.importTOML "${sdkSrc}/pyproject.toml").project.dependencies;

  # nixpkgs flags PyPDF2 3.0.1 as insecure; clear the gate for this package
  # only rather than relaxing the consumer's global insecure-package config.
  pypdf2 = python3Packages.pypdf2.overrideAttrs (old: {
    meta = old.meta // {
      knownVulnerabilities = [ ];
    };
  });

  karrio = python3Packages.buildPythonPackage {
    pname = "karrio";
    version = projectVersion sdkSrc;

    pyproject = true;

    src = sdkSrc;

    build-system = [ python3Packages.setuptools ];

    dependencies =
      with python3Packages;
      [
        attrs
        xmltodict
        lxml
        pillow
        phonenumbers
        python-barcode
        toml
        loguru
        jstruct
        py-soap
        lxml-stubs
        pypdf
      ]
      ++ lib.optional requiresPyPDF2 pypdf2;

    pythonRelaxDeps = true;

    pythonImportsCheck = [
      "karrio"
      "karrio.lib"
      "karrio.core.utils.helpers"
    ];

    # One entry per connector in `src`, keyed by its directory name with
    # underscores as dashes (dhl_freight_sweden -> dhl-freight-sweden), so the
    # set follows whichever karrio source the sdk is built from.
    passthru.optional-modules = lib.mapAttrs' (
      connectorPath: _:
      lib.nameValuePair (lib.replaceStrings [ "_" ] [ "-" ] connectorPath) (mkConnector connectorPath)
    ) (lib.filterAttrs (_: type: type == "directory") (builtins.readDir connectorsDir));

    meta = {
      description = "Multi-carrier shipping API integration with python";
      homepage = "https://github.com/karrioapi/karrio";
      license = lib.licenses.lgpl3Only;
    };
  };

  # Connectors are separate distributions that merge into the karrio.*
  # namespace packages and register a karrio.plugins entry point.
  mkConnector =
    connectorPath:
    let
      connectorSrc = "${connectorsDir}/${connectorPath}";
    in
    python3Packages.buildPythonPackage {
      pname = "karrio-${lib.replaceStrings [ "_" ] [ "-" ] connectorPath}";
      version = projectVersion connectorSrc;

      pyproject = true;
      src = connectorSrc;

      build-system = [ python3Packages.setuptools ];

      dependencies = [ karrio ];

      pythonRelaxDeps = true;

      pythonImportsCheck = map (kind: "karrio.${kind}.${connectorPath}") (
        lib.filter (kind: builtins.pathExists "${connectorSrc}/karrio/${kind}/${connectorPath}") [
          "mappers"
          "providers"
          "plugins"
        ]
      );

      meta = {
        description = "Karrio connector ${connectorPath}";
        homepage = "https://github.com/karrioapi/karrio";
        license = lib.licenses.lgpl3Only;
      };
    };
in
karrio
