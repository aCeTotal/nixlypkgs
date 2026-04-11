{
  stdenv,
  lib,
  fetchurl,
  cmake,
  doxygen,
  graphviz,
  pkg-config,
  autoPatchelfHook,
  kdePackages,
  alkimia,
  aqbanking,
  gmp,
  gwenhywfar,
  libical,
  libofx,
  sqlcipher,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "kmymoney";
  version = "5.2.2";

  src = fetchurl {
    url = "mirror://kde/stable/kmymoney/${finalAttrs.version}/kmymoney-${finalAttrs.version}.tar.xz";
    hash = "sha256-QLZjnmohYQDSAkjtdPoVQgL5zN+8M1Inztwb746l03c=";
  };

  cmakeFlags = [
    "-DBUILD_WITH_QT6=ON"
    "-DBUILD_TESTING=OFF"
  ];

  nativeBuildInputs = [
    cmake
    doxygen
    graphviz
    pkg-config
    python3.pkgs.wrapPython
  ] ++ (with kdePackages; [
    extra-cmake-modules
    wrapQtAppsHook
    kdoctools
    autoPatchelfHook
  ]);

  buildInputs = [
    alkimia
    aqbanking
    gmp
    gwenhywfar
    libical
    libofx
    sqlcipher
  ] ++ (with kdePackages; [
    akonadi
    karchive
    kcmutils
    kcontacts
    kcrash
    kdiagram
    kholidays
    kidentitymanagement
    kitemmodels
    plasma-activities
    qgpgme
    qtwebengine
  ]) ++ [
    python3.pkgs.woob
  ];

  postPatch = ''
    buildPythonPath "${python3.pkgs.woob}"
    patchPythonScript "kmymoney/plugins/woob/interface/kmymoneywoob.py"

    sed -i -e '1i import sys; sys.argv = [""]' \
      "kmymoney/plugins/woob/interface/kmymoneywoob.py"
  '';

  postFixup = ''
    patchelf --add-needed libpython${python3.pythonVersion}.so \
      "$out/bin/.kmymoney-wrapped"
  '';

  meta = {
    description = "Personal finance manager for KDE";
    mainProgram = "kmymoney";
    homepage = "https://kmymoney.org/";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl2Plus;
  };
})
