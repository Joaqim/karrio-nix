{
  buildPythonPackage,
  fetchPypi,
  lib,
  six,
  lxml,
}:
buildPythonPackage rec {
  pname = "py-soap";
  version = "2026.1.32";

  # Only a wheel is published to PyPI; there is no source distribution.
  format = "wheel";

  # the wheel filename uses the underscore-normalized project name
  src = fetchPypi {
    pname = "py_soap";
    inherit version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-zcK776i0TCNB5tkbu+i/eLkMjY7gtSvqKNKixcAYm7k=";
  };

  dependencies = [
    six
    lxml
  ];

  pythonImportsCheck = [ "pysoap" ];

  meta = {
    description = "SOAP client library";
    homepage = "https://pypi.org/project/py-soap/";
    license = lib.licenses.lgpl3Only;
  };
}
