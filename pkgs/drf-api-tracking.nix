{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  djangorestframework,
  pytz,
}:
buildPythonPackage rec {
  pname = "drf-api-tracking";
  version = "1.8.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-DwhUefxnyNTS5ajVBZv+hT7tK6LU7EBj+lQ40Rs/aHw=";
  };

  build-system = [ setuptools ];

  dependencies = [
    djangorestframework
    pytz
  ];

  # Importing the app requires configured Django settings; the karrio-server
  # env build and `karrio --help` are the real integration check.
  doCheck = false;

  meta = {
    description = "DRF API request/response logging";
    homepage = "https://github.com/lingster/drf-api-tracking";
    license = lib.licenses.bsd2;
  };
}
