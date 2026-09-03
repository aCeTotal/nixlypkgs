{ lib
, stdenv
, fetchFromGitHub
, cmake
, vulkan-headers
, vulkan-loader
, vulkan-utility-libraries
}:

stdenv.mkDerivation rec {
  pname = "low-latency-layer";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "Korthos-Software";
    repo = "low_latency_layer";
    rev = "v${version}";
    hash = "sha256-mnGAH0m19wOkWEowpcPRHXQSc6HGYW+CFYxjPF2onk4=";
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
