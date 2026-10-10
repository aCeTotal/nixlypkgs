{
  lib,
  runCommand,
  stdenvNoCC,
  stdenv,
  python3,
  patchelf,
  openssl,
  cacert,
  src,
  manifest,
  gitdeps,
  hash,
}:

let
  prefixes = [
    "Directory.Build."
    "Engine/Source/Programs/"
    "Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64/"
  ];

  # NuGet packages for UBT and UAT.
  fetched = stdenvNoCC.mkDerivation {
    name = "ue5-nuget";

    dontUnpack = true;
    nativeBuildInputs = [
      python3
      patchelf
    ];

    env = {
      DOTNET_CLI_TELEMETRY_OPTOUT = "1";
      DOTNET_NOLOGO = "1";
      DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
      DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      LD_LIBRARY_PATH = lib.makeLibraryPath [
        stdenv.cc.cc.lib
        openssl
      ];
    };

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR"
      tree="$TMPDIR/tree"
      cp -rs ${src} "$tree"
      find "$tree" -type d -exec chmod u+w {} +
      python3 ${./gitdeps.py} extract ${manifest} ${gitdeps prefixes} "$tree" ${lib.escapeShellArgs prefixes}

      dotnet="$tree/Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64/dotnet"
      patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$dotnet"

      cd "$tree/Engine"
      {
        find Source/Programs/UnrealBuildTool Source/Programs/AutomationTool -name '*.csproj'
        find . -name '*.Automation.csproj' -printf '%P\n'
      } | sort -u | while IFS= read -r project; do
        "$dotnet" restore "$project" --packages "$out"
      done

      runHook postBuild
    '';

    dontInstall = true;
    dontFixup = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = hash;
  };
in
# Native tools inside packages, patched.
runCommand "ue5-nuget-patched" { nativeBuildInputs = [ patchelf ]; } ''
  cp -r --reflink=auto ${fetched} "$out"
  chmod -R u+w "$out"
  interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"
  find "$out" -type f | while IFS= read -r file; do
    patchelf --print-interpreter "$file" >/dev/null 2>&1 || continue
    patchelf --set-interpreter "$interp" "$file"
  done
''
