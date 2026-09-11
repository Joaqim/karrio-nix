{
  lib,
  fetchFromGitHub,
  python3Packages,
  jstruct,
  py-soap,
  lxml-stubs,
  ...
}:
let
  version = "2026.1.32";
  rev = "b9a8d66b43f3b6d00e714665b244576a7a57bd20";

  # Sparse fetch rooted at one module directory; one rev shared by the sdk
  # and every optional module keeps them pinned together.
  mkKarrioSrc =
    sparseCheckout: rootDir: hash:
    fetchFromGitHub {
      owner = "Joaqim";
      repo = "karrio";
      inherit
        rev
        sparseCheckout
        rootDir
        hash
        ;
      fetchSubmodules = false;
    };

  karrio = python3Packages.buildPythonPackage {
    pname = "karrio";
    inherit version;

    pyproject = true;

    src = mkKarrioSrc [
      "modules/sdk"
    ] "modules/sdk" "sha256-1VzotfbxnIulrmAkXc87ysZYJ/5KHksafAh955228BQ=";

    build-system = [ python3Packages.setuptools ];

    dependencies = with python3Packages; [
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
    ];

    pythonRelaxDeps = true;

    pythonImportsCheck = [
      "karrio"
      "karrio.lib"
      "karrio.core.utils.helpers"
    ];

    passthru.optional-modules = {
      dhl-freight-sweden = mkConnector {
        pname = "karrio-dhl-freight-sweden";
        connectorVersion = "2026.4";
        connectorPath = "dhl_freight_sweden";
        description = "Karrio connector for DHL Freight Sweden";
        hash = "sha256-h9vPRGazoYLyBM29g6WztYyHQSTXITlFjljIikkT25o=";
        pythonImportsCheck = [
          "karrio.mappers.dhl_freight_sweden"
          "karrio.providers.dhl_freight_sweden"
          "karrio.plugins.dhl_freight_sweden"
        ];
      };
      postnord = mkConnector {
        pname = "karrio-postnord";
        connectorVersion = "2026.6";
        connectorPath = "postnord";
        description = "Karrio connector for PostNord";
        hash = "sha256-FvY4fZn8faXzSonLuO7iiogvWsbD2wUHXmLm6iKd6sY=";
        pythonImportsCheck = [
          "karrio.mappers.postnord"
          "karrio.providers.postnord"
          "karrio.plugins.postnord"
        ];
      };
    };

    meta = {
      description = "Multi-carrier shipping API integration with python";
      homepage = "https://github.com/karrioapi/karrio";
      license = lib.licenses.lgpl3Only;
    };
  };

  # Connectors are separate distributions that merge into the karrio.*
  # namespace packages and register a karrio.plugins entry point.
  mkConnector =
    {
      pname,
      connectorVersion,
      connectorPath,
      description,
      hash,
      pythonImportsCheck,
    }:
    python3Packages.buildPythonPackage {
      inherit pname pythonImportsCheck;
      version = connectorVersion;

      pyproject = true;
      src = mkKarrioSrc [
        "modules/connectors/${connectorPath}"
      ] "modules/connectors/${connectorPath}" hash;

      build-system = [ python3Packages.setuptools ];

      dependencies = [ karrio ];

      pythonRelaxDeps = true;

      meta = {
        inherit description;
        homepage = "https://github.com/karrioapi/karrio";
        license = lib.licenses.lgpl3Only;
      };
    };
in
karrio
