{
  buildPythonPackage,
  fetchPypi,
  lib,
  setuptools,
}:
buildPythonPackage rec {
  pname = "lxml-stubs";
  version = "0.5.1";

  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-4Owqoc6S2RJ4txkJHORRXBKtwdVkNZ36+B76fU/qt50=";
  };

  build-system = [ setuptools ];

  # PEP 561 stub-only package: ships *.pyi files under lxml-stubs/, which is
  # not an importable module, so there is nothing for pythonImportsCheck
  meta = {
    description = "Type annotations for the lxml package";
    homepage = "https://github.com/lxml/lxml-stubs";
    license = lib.licenses.asl20;
  };
}
