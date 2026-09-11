# Python package-set overrides for karrio dependencies absent from nixpkgs.
# Consumed by both flake.nix (`nix develop`) and shell.nix (`nix-shell`) so the
# two entry points stay in sync. Apply via:
#   python3.override { self = python; packageOverrides = import ./python-overlay.nix; }
pyfinal: pyprev: {
  django-constance = pyfinal.callPackage ./pkgs/django-constance.nix { };
  jstruct = pyfinal.callPackage ./pkgs/jstruct.nix { };
  generateDS = pyfinal.callPackage ./pkgs/generateds.nix { };
  django-downloadview = pyfinal.callPackage ./pkgs/django-downloadview.nix { };
  django-email-verification = pyfinal.callPackage ./pkgs/django-email-verification.nix { };
  drf-api-tracking = pyfinal.callPackage ./pkgs/drf-api-tracking.nix { };
  pyzint = pyfinal.callPackage ./pkgs/pyzint.nix { };
  jsonfield = pyfinal.callPackage ./pkgs/jsonfield.nix { };

  # karrio targets Django 6. Point the whole package set at django_6 so the DRF
  # and django-* ecosystem propagate a single Django, eliminating the buildEnv
  # collision from mixing the default django (5.2) with an explicit django_6.
  # django_6 is a standalone attribute (not defined via `django`), so this
  # override does not recurse.
  django = pyprev.django_6;

  # nixpkgs' python-barcode installs its docs/ tree (including a conf.py) into
  # site-packages, colliding with cryptography's docs/conf.py under withPackages'
  # buildEnv. Drop the stray docs directory.
  python-barcode = pyprev.python-barcode.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -rf "$out/${pyprev.python.sitePackages}/docs"
    '';
  });

  # karrio pins django-health-check==4.4.2, which renamed the class-based view
  # from MainView to HealthCheckView (karrio's core/urls.py imports the latter).
  # The pinned nixpkgs still ships 3.20.8 (upstream repo moved from
  # KristianOellegaard to codingjoe between these releases), so bump the source
  # to the required tag. flit-scm derives the version from
  # SETUPTOOLS_SCM_PRETEND_VERSION, which overrideAttrs' version sets.
  django-health-check = pyprev.django-health-check.overrideAttrs (old: rec {
    version = "4.4.2";
    src = pyfinal.pkgs.fetchFromGitHub {
      owner = "codingjoe";
      repo = "django-health-check";
      tag = version;
      hash = "sha256-O/s++NN07B6I8YVi2HetIRY9IPtnh6Br5QzSH61NQy0=";
    };
    # 4.4.2 adds a dnspython runtime dependency absent from the 3.20.8 recipe.
    # overrideAttrs bypasses buildPythonPackage's dependencies->propagated
    # wiring, so extend propagatedBuildInputs directly.
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ pyfinal.dnspython ];
    # 4.4.2 imports Django settings at module import time; the upstream test
    # suite and pythonImportsCheck both require configured settings. The
    # karrio-server env build plus `karrio migrate` are the real integration
    # check, mirroring the other local karrio dependency derivations.
    doCheck = false;
    dontUsePytestCheck = true;
    pythonImportsCheck = [ ];
  });
}
