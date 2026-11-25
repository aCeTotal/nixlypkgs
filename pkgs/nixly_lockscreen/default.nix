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
  source = lib.importJSON ./source.json;
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
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "aCeTotal";
    repo = "nixly_lockscreen";
    inherit (source) rev hash;
  };

  inherit (source) cargoHash;

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
