# Raw STM32CubeIDE tree extracted from ST's generic Linux installer.
# No patchelf here: the bundled JRE, GCC toolchain and gdbserver are run
# inside an FHS sandbox (see fhs.nix), so binaries stay untouched.
{ lib
, stdenvNoCC
, requireFile
, gnutar
, gzip
, xz
, file
, which

  # Version of the generic Linux installer.
, version ? "2.2.0"
  # Set to the real sha256 of your downloaded .sh installer.
  # Get it with:  nix hash file <installer>.sh
, sha256 ? lib.fakeSha256
}:

stdenvNoCC.mkDerivation {
  pname = "stm32cubeide-unwrapped";
  inherit version;

  # ST gates the download behind a login, so we cannot fetch it.
  # Download the "Generic Linux Installer" from
  #   https://www.st.com/en/development-tools/stm32cubeide.html
  # unzip it to get the .sh, rename to the name below, then add to the store.
  src = requireFile {
    name = "stm32cubeide-${version}-Lin-x86_64.sh";
    inherit sha256;
    message = ''
      STM32CubeIDE ${version} installer not found in the Nix store.

      1. Download "STM32CubeIDE Generic Linux Installer" (needs an ST login):
           https://www.st.com/en/development-tools/stm32cubeide.html
      2. Unzip it. You get a file like
           stm32cubeide_${version}_<build>_<date>-Lin-x86_64.sh
      3. Rename it exactly to:
           stm32cubeide-${version}-Lin-x86_64.sh
      4. Compute its hash and set it as the `sha256` arg of this package:
           nix hash file stm32cubeide-${version}-Lin-x86_64.sh
      5. Add the file to the store:
           nix-store --add-fixed sha256 stm32cubeide-${version}-Lin-x86_64.sh
    '';
  };

  nativeBuildInputs = [ gnutar gzip xz file which ];

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  # The installer is a makeself archive. --noexec extracts the payload
  # without running the interactive installer.
  unpackPhase = ''
    runHook preUnpack
    cp "$src" installer.sh
    chmod +w installer.sh
    sh installer.sh --quiet --noexec --nox11 --target payload
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Inside the makeself payload the IDE ships as a single tarball.
    tarball=$(find payload -maxdepth 2 -name 'stm32cubeide*-Lin.tar.gz' | head -n1)
    if [ -z "$tarball" ]; then
      echo "error: could not locate the IDE tarball in the installer payload" >&2
      find payload -maxdepth 2 -type f >&2
      exit 1
    fi

    mkdir -p unpacked
    tar -xf "$tarball" -C unpacked

    # Normalise to a fixed location regardless of whether the tarball has a
    # single top-level directory or not.
    mkdir -p "$out"
    top=$(ls -1 unpacked)
    if [ "$(echo "$top" | wc -l)" -eq 1 ] && [ -d "unpacked/$top" ]; then
      mv "unpacked/$top" "$out/stm32cubeide"
    else
      mkdir -p "$out/stm32cubeide"
      mv unpacked/* "$out/stm32cubeide/"
    fi

    # Sanity check: the native launcher must be where fhs.nix expects it.
    if [ ! -e "$out/stm32cubeide/stm32cubeide" ]; then
      echo "error: launcher not found at $out/stm32cubeide/stm32cubeide" >&2
      find "$out/stm32cubeide" -maxdepth 1 >&2
      exit 1
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "STM32CubeIDE Eclipse tree (unwrapped, run via FHS)";
    homepage = "https://www.st.com/en/development-tools/stm32cubeide.html";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
