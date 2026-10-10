{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  innoextract,
  cabextract,
  unzip,
  zstd,
  icoutils,
  makeWrapper,
  addDriverRunpath,
  coreutils,
  jq,
  dxvk,
  pkgsCross,
  wineWow64Packages,
}:

let
  innoextract64 = innoextract.overrideAttrs (old: {
    version = "1.9.2026.02.23";
    src = fetchFromGitHub {
      owner = "UserUnknownFactor";
      repo = "innoextract_win";
      rev = "e561d8cb6004776eecb3184c0d56b3534a0c7e15";
      hash = "sha256-+XFuDq9ILj0J1e2BYznR8pieANNn1xEA7e1FmadWSb4=";
    };
    patches = [ ];
  });

  crackEngineDll = fetchurl {
    url = "https://aceclan.no/derivations_source/Gaea/crack/Gaea.Engine.dll";
    hash = "sha256-pR8R0zaed9yCeQPC8jwKloS2Ahx77842oGcWr/OlW44=";
  };

  wine = wineWow64Packages.stagingFull;

  dotnetVersion = "8.0.29";

  dotnetRuntime = fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/Runtime/${dotnetVersion}/dotnet-runtime-${dotnetVersion}-win-x64.zip";
    hash = "sha256-iuwXjoukUIXgP2iNZDD7GSJwcmWeeUGGsPF5SsWgBNg=";
  };

  dotnetDesktop = fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${dotnetVersion}/windowsdesktop-runtime-${dotnetVersion}-win-x64.zip";
    hash = "sha256-fr8NLHHAu1bRYL5egYoAgc1V6CoQZIFKL6+rAK7IXqg=";
  };

  vcRedist = fetchurl {
    url = "https://download.visualstudio.microsoft.com/download/pr/bd1c8d9d-ba95-4eee-bc6e-df1fcc876373/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe";
    hash = "sha256-zA/w6x3D9RiK5jAPrvMr9b7rpL3W6ORFqRhAcglrcTs=";
  };

  nvidiaLibsVersion = "1.0.2";
  nvidiaLibs = fetchurl {
    url = "https://github.com/SveSop/nvidia-libs/releases/download/v${nvidiaLibsVersion}/nvidia-libs-v${nvidiaLibsVersion}.tar.xz";
    hash = "sha256-Aei7Y2jQiOItjo8dAklyFOjbQ2R2Ahcl7wwHB7fLFzg=";
  };

  embedHelper = pkgsCross.mingwW64.stdenv.mkDerivation {
    pname = "gaea-embed";
    version = "1";
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      $CC -O2 -mwindows -o gaea-embed.exe ${./gaea-embed.c} -luser32
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 gaea-embed.exe $out/bin/gaea-embed.exe
      runHook postInstall
    '';
  };

  vkd3dProtonVersion = "2.14.1";
  vkd3dProton = fetchurl {
    url = "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${vkd3dProtonVersion}/vkd3d-proton-${vkd3dProtonVersion}.tar.zst";
    hash = "sha256-rHDM/gHWELUcpnoKROTyT12inGZfrMDC+vR+CBjSMWg=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gaea";
  version = "2.3.0.1";

  src = fetchurl {
    urls = [
      "https://aceclan.no/derivations_source/Gaea/Gaea-${finalAttrs.version}.exe"
      "https://get.gaea.app/Release/Gaea-${finalAttrs.version}.exe"
    ];
    hash = "sha256-GtwioEz5r0czhVFrnE6zagnCajFMOP+p4XpFrrv56Ss=";
  };

  nativeBuildInputs = [
    innoextract64
    cabextract
    unzip
    zstd
    icoutils
    makeWrapper
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    innoextract --extract --silent --include app --output-dir . "$src"
    install -d $out/share/gaea
    mv app $out/share/gaea/app

    install -Dm644 ${crackEngineDll} $out/share/gaea/app/Gaea.Engine.dll

    # Wine's builtin ConcRT busy-spins.
    cabextract -q -d vcredist ${vcRedist}
    cabextract -q -F '*.dll_amd64' -d vcrt vcredist/a12
    for dll in concrt140 msvcp140 vcruntime140 vcruntime140_1 vcomp140; do
      install -Dm644 vcrt/$dll.dll_amd64 $out/share/gaea/app/$dll.dll
    done

    unzip -q ${dotnetRuntime} -d $out/share/gaea/dotnet
    unzip -q ${dotnetDesktop} -d $out/share/gaea/dotnet

    tar --zstd -xf ${vkd3dProton} -C .
    install -Dm644 -t $out/share/gaea/vkd3d \
      vkd3d-proton-${vkd3dProtonVersion}/x64/d3d12.dll \
      vkd3d-proton-${vkd3dProtonVersion}/x64/d3d12core.dll

    tar -xf ${nvidiaLibs} -C .
    install -Dm644 -t $out/share/gaea/nvlibs \
      nvidia-libs-v${nvidiaLibsVersion}/x64/nvcuda.dll

    install -Dm644 ${embedHelper}/bin/gaea-embed.exe \
      $out/share/gaea/embed/gaea-embed.exe

    mkdir icons && (cd icons && icotool -x $out/share/gaea/app/Gaea-2.ico)
    install -Dm644 icons/*_512x512x32.png \
      $out/share/icons/hicolor/512x512/apps/gaea.png

    install -Dm755 ${./launcher.sh} $out/bin/gaea
    substituteInPlace $out/bin/gaea \
      --subst-var out \
      --subst-var-by dxvk ${dxvk.bin} \
      --subst-var-by driverLink ${addDriverRunpath.driverLink}
    wrapProgram $out/bin/gaea \
      --prefix PATH : ${
        lib.makeBinPath [
          wine
          coreutils
          jq
        ]
      }

    install -Dm644 ${./gaea.desktop} $out/share/applications/gaea.desktop

    runHook postInstall
  '';

  meta = {
    description = "QuadSpinner Gaea 2 terrain designer, Windows-build under Wine";
    homepage = "https://quadspinner.com/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "gaea";
  };
})
