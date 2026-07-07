{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  django,
  requests,
}:
buildPythonPackage rec {
  pname = "django-downloadview";
  version = "2.5.0";
  pyproject = true;

  src = fetchPypi {
    # The published sdist normalizes the name with an underscore
    # (django_downloadview-2.5.0.tar.gz), which fetchPypi will not derive from a
    # hyphenated pname.
    pname = "django_downloadview";
    inherit version;
    hash = "sha256-O/CwaUcRyttKnBFzyyEFWj874UwJLhMuw9afFLTY/f4=";
  };

  # Version is resolved by setuptools_scm; the sdist carries no git metadata, so
  # pin it explicitly.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    django
    requests
  ];

  # Importing the app requires configured Django settings; the karrio-server
  # env build and `karrio --help` are the real integration check.
  doCheck = false;

  meta = {
    description = "Serve files with Django";
    homepage = "https://github.com/benoitbryon/django-downloadview";
    license = lib.licenses.bsd3;
  };
}
