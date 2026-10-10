{
  lib,
  stdenvNoCC,
  stdenv,
  callPackage,
  python3,
  rsync,
  patchelf,
  util-linux,
  which,
  procps,
  bash,
}:

let
  version = "5.8.3";

  # Private fork, fetched via SSH.
  src = builtins.fetchGit {
    url = "ssh://git@github.com/aCeTotal/UnrealEngine_Wayland.git";
    ref = "release";
    rev = "396c9f059903aed5fec78ecd3d437a40c6415368";
    shallow = true;
  };

  manifest = "${src}/Engine/Build/Commit.gitdeps.xml";
  sdk = lib.importJSON "${src}/Engine/Config/Linux/Linux_SDK.json";

  toolchain = callPackage ./toolchain.nix {
    version = sdk.MainVersion;
    hash = "sha256-bu9CZ5t0TNy1Anby18/wpR993WMpYOBr+8P2uVCO9hU=";
  };
  gitdeps = callPackage ./gitdeps.nix { inherit manifest; };
  nuget = callPackage ./nuget.nix {
    inherit src manifest gitdeps;
    hash = "sha256-6DkT8Rk3jWb1lUcDU+JaPxLujp6MTCTD7gcbi/5qiP8=";
  };
  launchers = callPackage ../unreal_editor/launchers.nix { };

  # Persistent tree for incremental builds.
  workspace = "/var/cache/ue5";
  sdkDir = "Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/${sdk.MainVersion}";
  dotnetDir = "Engine/Binaries/ThirdParty/DotNet/10.0/linux-x64";

  # Compile job RAM budget.
  jobMemKiB = 2 * 1024 * 1024;

  # Prebuilt tools run during build.
  hostTools = [
    "Engine/Binaries/Linux/dump_syms"
    "Engine/Binaries/Linux/BreakpadSymbolEncoder"
    "Engine/Source/ThirdParty/Intel/ISPC/bin/Linux/ispc"
    "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool"
  ];

  buildGraphArgs = [
    "BuildGraph"
    "-script=Engine/Build/InstalledEngineBuild.xml"
    "-target=Make Installed Build Linux"
    "-set:HostPlatformOnly=true"
    "-set:WithLinuxArm64=false"
    "-set:WithDDC=false"
    "-set:GameConfigurations=Development;Shipping"
    "-set:BuiltDirectory=${workspace}/installed"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "ue5-source";
  inherit version;

  nativeBuildInputs = [
    python3
    rsync
    patchelf
    util-linux
    which
    procps
  ];

  env = {
    HOME = "${workspace}/home";
    NUGET_PACKAGES = "${nuget}";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_NOLOGO = "1";
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
    DOTNET_NUGET_SIGNATURE_VERIFICATION = "false";
    LD_LIBRARY_PATH = lib.makeLibraryPath [ stdenv.cc.cc.lib ];
    # x86-64-v3, like the nixlyos kernel.
    UnrealBuildTool_BuildConfiguration__MinCpuArchX64 = "AVX2";
  };

  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    if [ ! -w ${workspace} ]; then
      echo "${workspace} is not writable in the sandbox; enable nixlyos.ue5" >&2
      exit 1
    fi
    umask 007
    exec 9>${workspace}/lock
    flock 9

    tree=${workspace}/tree
    mkdir -p "$tree" "$HOME"

    (cd ${src} && find . ! -type d -printf '%P\n' | sort) > "$TMPDIR/src.list"
    if [ -f ${workspace}/src.list ]; then
      comm -23 ${workspace}/src.list "$TMPDIR/src.list" \
        | (cd "$tree" && xargs -d '\n' -r rm -f --)
    fi
    rsync -rlcE --chmod=ug+w ${src}/ "$tree/"
    mv "$TMPDIR/src.list" ${workspace}/src.list

    python3 ${./gitdeps.py} extract ${manifest} ${gitdeps [ ]} "$tree"

    interp="$(cat ${stdenv.cc}/nix-support/dynamic-linker)"
    cd "$tree"
    # Bundled singlefilehost breaks under patchelf.
    {
      printf '%s\n' ${lib.escapeShellArgs hostTools}
      find ${dotnetDir} -type f \( -perm -u+x -o -name apphost \) ! -name singlefilehost
    } | while IFS= read -r tool; do
      current="$(patchelf --print-interpreter "$tool" 2>/dev/null)" || continue
      [ "$current" = "$interp" ] || patchelf --set-interpreter "$interp" "$tool"
    done
    find Engine/Build -name '*.sh' -exec sed -i '1s|^#!/bin/bash|#!${bash}/bin/bash|' {} +
    mkdir -p "$(dirname ${sdkDir})"
    ln -sfn ${toolchain} ${sdkDir}

    # Feature packs run UnrealPak mid-graph.
    sed -i 's|LaunchModuleName = "UnrealPak";|&\n\t\tPostBuildSteps.Add("${patchelf}/bin/patchelf --set-interpreter '"$interp"' $(EngineDir)/Binaries/Linux/UnrealPak");|' \
      Engine/Source/Programs/UnrealPak/UnrealPak.Target.cs
    # DebugGame editor doubles compile time.
    sed -i '/Target="UnrealEditor" Platform="Linux" Configuration="DebugGame"/d' \
      Engine/Build/InstalledEngineBuild.xml

    cat > NuGet.Config <<EOF
    <?xml version="1.0" encoding="utf-8"?>
    <configuration>
      <packageSources>
        <clear />
        <add key="nix" value="${nuget}" />
      </packageSources>
    </configuration>
    EOF

    # lscpu needs /sys, absent in sandbox.
    jobs="$(nproc)"
    memJobs="$(awk '/^MemTotal:/ { print int($2 / ${toString jobMemKiB}) }' /proc/meminfo)"
    if [ "$memJobs" -lt "$jobs" ]; then
      jobs="$memJobs"
    fi
    export UnrealBuildTool_BuildConfiguration__MaxParallelActions="$jobs"

    Engine/Build/BatchFiles/RunUAT.sh ${lib.escapeShellArgs buildGraphArgs}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    umask 022
    engine="$out/opt/UnrealEngine"
    mkdir -p "$engine"
    cp -r --reflink=auto ${workspace}/installed/Linux/. "$engine/"
    chmod -R go-w,g-s "$engine"
    find "$engine" -name '*.debug' -delete
    rm -rf "$engine/${sdkDir}"
    ln -s ${toolchain} "$engine/${sdkDir}"

    ${launchers.install {
      id = "ue5-wayland";
      name = "Unreal Editor (Wayland)";
      comment = "Unreal Engine ${version} editor, native Wayland";
      driver = "wayland";
      state = "UnrealEngineWayland";
      resources = "${workspace}/tree/Engine/Source/Runtime/Launch/Resources";
    }}

    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "Unreal Engine ${version} editor built from the Wayland fork";
    homepage = "https://github.com/aCeTotal/UnrealEngine_Wayland";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "UnrealEditor";
    hydraPlatforms = [ ];
  };
}
