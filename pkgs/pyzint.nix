{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  cython,
  libzint,
}:
buildPythonPackage rec {
  pname = "pyzint";
  version = "0.1.10";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-6fBFwrJTXJqjhcHHlafU9uhbtWrfi6Mrtsc3xI7Z4Qk=";
  };

  build-system = [
    setuptools
    cython
  ];

  buildInputs = [ libzint ];

  # pyzint 0.1.10 ships 2021-era C (pyzint/zint.c) that passes a char(*)[50]
  # where a char* is expected. GCC 15 promotes -Wincompatible-pointer-types to
  # an error by default; demote it (and the deprecated PyEval_InitThreads
  # warning) so the extension compiles against the modern toolchain.
  env.NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types -Wno-deprecated-declarations";

  pythonImportsCheck = [ "pyzint" ];

  meta = {
    description = "Python binding for the zint barcode library";
    homepage = "https://github.com/mosquito/pyzint";
    license = lib.licenses.asl20;
  };
}
