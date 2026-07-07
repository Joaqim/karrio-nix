{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  django,
}:
buildPythonPackage rec {
  pname = "jsonfield";
  version = "3.2.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-ylOHG8MwiuT0zdw7T5ntXG/Gq7GDL7+0mbxtpWbHDko=";
  };

  build-system = [ setuptools ];

  dependencies = [ django ];

  # Upstream tests require a configured Django project; the karrio-server env
  # build and `karrio migrate` are the real integration check.
  doCheck = false;

  pythonImportsCheck = [ "jsonfield" ];

  meta = {
    description = "Reusable Django field for storing validated JSON in a model";
    homepage = "https://github.com/rpkilby/jsonfield";
    license = lib.licenses.mit;
  };
}
