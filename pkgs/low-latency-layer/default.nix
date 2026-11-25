{ lib
, stdenv
, fetchFromGitHub
, cmake
, vulkan-headers
, vulkan-loader
, vulkan-utility-libraries
}:

let
  source = lib.importJSON ./source.json;
in
stdenv.mkDerivation rec {
  pname = "low-latency-layer";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "Korthos-Software";
    repo = "low_latency_layer";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ vulkan-headers vulkan-loader vulkan-utility-libraries ];

  meta = with lib; {
    description = "Implicit Vulkan layer providing VK_NV_low_latency2 (Reflex) and VK_AMD_anti_lag on any GPU";
    homepage = "https://github.com/Korthos-Software/low_latency_layer";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
