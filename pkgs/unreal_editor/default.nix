{
  lib,
  stdenvNoCC,
  stdenv,
  callPackage,
  fetchurl,
  unzip,
  patchelf,
  bash,
}:

let
  version = "5.8.0";
  base = "https://aceclan.no/derivations_source/UE5/${version}";
  launchers = callPackage ./launchers.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "unreal-editor";
  inherit version;

  srcs = [
    (fetchurl {
      url = "${base}/Linux_Unreal_Engine_${version}.zip";
      hash = "sha256-1vykNfRUFQiwUq/rfPe4g0TuSokUpPka5J9T6gTtkXQ=";
    })
    (fetchurl {
      url = "${base}/Linux_Bridge_${version}_2025.0.1.zip";
      hash = "sha256-iycPft3pxCHgT4+5GOQVNzWgEJdmn1Lmqsq39en28kg=";
    })
    (fetchurl {
      url = "${base}/Linux_Fab_${version}_0.0.13.zip";
      hash = "sha256-Cy2ynW7/tkPWSDiNmkIdzC030EEA8NcotzjKuHTX5c0=";
    })
  ];

  nativeBuildInputs = [
    unzip
    patchelf
  ];

  dontUnpack = true;

  dontFixup = true;

  installPhase = ''
    runHook preInstall

    engine="$out/opt/UnrealEngine"
    install -dm755 "$engine"

    for archive in $srcs; do
      echo "extracting $archive"
      unzip -qq -o "$archive" -d "$engine"
    done

    find "$engine" \( -name '*.debug' -o -name '*.sym' -o -name '*.pdb' \) -delete
    rm -rf \
      "$engine/Engine/Binaries/Android" \
      "$engine/Engine/Binaries/LinuxArm64" \
      "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-arm64" \
      "$engine/Engine/Intermediate/Build/Android" \
      "$engine/Engine/Intermediate/Build/LinuxArm64"

    chmod -R u+w "$engine"
    chmod +x "$engine/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64/dotnet"
    find "$engine" -type f -name '*.sh' -exec chmod +x {} +

    interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"
    libs="${lib.makeLibraryPath launchers.runtimeLibs}"
    patched=0
    while IFS= read -r -d "" f; do
      if [ -n "$(patchelf --print-interpreter "$f" 2>/dev/null)" ]; then
        patchelf --set-interpreter "$interp" "$f"
        old="$(patchelf --print-rpath "$f" 2>/dev/null || true)"
        patchelf --set-rpath "''${old:+$old:}$libs" "$f"
        patched=$((patched + 1))
      fi
    done < <(find "$engine" -type f -perm -u+x -print0)
    echo "patched interpreter and rpath on $patched executables"

    # Unpatchable; launcher binds /lib64.
    chmod +x "$engine/Engine/Plugins/Bridge/ThirdParty/Linux/node-bifrost"

    find "$engine" -type f -name '*.sh' \
      -exec sed -i '1s|^#!/bin/bash|#!${bash}/bin/bash|' {} +

    ${launchers.install {
      id = "unreal-editor";
      name = "Unreal Editor";
      comment = "Unreal Engine ${version} editor";
      driver = "\${UE5_VIDEODRIVER:-x11}";
      state = "UnrealEngine";
      resources = "$engine/Engine/Source/Runtime/Launch/Resources";
    }}

    runHook postInstall
  '';

  meta = {
    description = "Unreal Engine ${version} editor (Epic's prebuilt Linux installed build)";
    homepage = "https://www.unrealengine.com/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "UnrealEditor";
    hydraPlatforms = [ ];
  };
}
