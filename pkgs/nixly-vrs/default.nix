{ lib
, stdenv
, vulkan-headers
, nixlytile
}:

stdenv.mkDerivation {
  pname = "nixly-vrs";
  inherit (nixlytile) version;

  src = "${nixlytile.src}/vrslayer";

  buildInputs = [ vulkan-headers ];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
    "BITS=${if stdenv.hostPlatform.is64bit then "64" else "32"}"
  ];

  meta = with lib; {
    description = "Vulkan layer behind nixlytile's dynamic rendering (variable rate shading)";
    homepage = "https://github.com/aCeTotal/nixlytile";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
