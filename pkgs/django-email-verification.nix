{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  django,
  deprecation,
  pyjwt,
  validators,
}:
buildPythonPackage rec {
  pname = "django-email-verification";
  version = "0.3.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-2hEEAESfFeIA4nzOHd8yr6zTYcHqcQ3NGPEkRBCnPx4=";
  };

  # The 0.3.3 sdist's setup.py reads LONG_DESCRIPTION.md, but only README.md is
  # shipped in the archive; point it at the file that exists.
  postPatch = ''
    substituteInPlace setup.py \
      --replace-fail "LONG_DESCRIPTION.md" "README.md"
  '';

  build-system = [ setuptools ];

  dependencies = [
    django
    deprecation
    pyjwt
    validators
  ];

  # Importing the app requires configured Django settings; the karrio-server
  # env build and `karrio --help` are the real integration check.
  doCheck = false;

  meta = {
    description = "Django email verification for custom user models";
    homepage = "https://github.com/LeoneBacciu/django-email-verification";
    license = lib.licenses.mit;
  };
}
