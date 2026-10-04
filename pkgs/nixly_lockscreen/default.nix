{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, makeWrapper
, autoPatchelfHook
, wayland
, wayland-protocols
, libxkbcommon
, vulkan-loader
, libGL
, libglvnd
, mesa
, libdrm
, libgbm
, fontconfig
, freetype
, linux-pam
, udev
}:

let
  runtimeLibs = [
    wayland
    libxkbcommon
    vulkan-loader
    libGL
    libglvnd
    mesa
    libdrm
    libgbm
    fontconfig
    freetype
    linux-pam
    udev
  ];
in
rustPlatform.buildRustPackage {
  pname = "nixly_lockscreen";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixly_lockscreen";
    rev = "4f7f55259da43aa702b665e85e6968682b3c703b";
    hash = "sha256-4qr2oOnadu2aTlnD8m6UGqpZqhBG9iDnMVlqOxI/6sE=";
  };

  cargoHash = "sha256-iW+2iVpjFUbtMzJ2ERlDOM9u7M4vxaGhrpYPmQhvWhY=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = runtimeLibs ++ [
    wayland-protocols
  ];

  postFixup = ''
    for bin in $out/bin/*; do
      patchelf --add-rpath "${lib.makeLibraryPath runtimeLibs}" "$bin" || true
      wrapProgram "$bin" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    done
  '';

  meta = with lib; {
    description = "Wayland session lockscreen with Matrix rain, blur and PAM";
    homepage = "https://github.com/aCeTotal/nixly_lockscreen";
    mainProgram = "nixly-lockscreen";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
