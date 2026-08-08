# QuadSpinner Gaea 2 (Windows-app) kjoert under Wine.
#
# GaeaSetup.exe paa aceclan.no er kun en web-bootstrapper: den laster ned
# Gaea-<versjon>.exe (Inno Setup) fra get.gaea.app. Vi henter den ekte
# installeren direkte og pakker den ut med innoextract, slik at bygget er
# hermetisk. aceclan.no proeves foerst som speil.
{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  innoextract,
  unzip,
  zstd,
  icoutils,
  makeWrapper,
  coreutils,
  dxvk,
  wineWow64Packages,
}:

let
  # nixpkgs' innoextract (1.9/1.10-dev) stopper ved Inno Setup 6.3.3.
  # Gaea-2.3.0.1.exe er bygget med Inno Setup 6.4.3, som krever nyere
  # header-parsing. Denne forken dekker 1.2.10 t.o.m. 6.7.0.
  innoextract64 = innoextract.overrideAttrs (old: {
    version = "unstable-2026-02-23-inno67";
    src = fetchFromGitHub {
      owner = "UserUnknownFactor";
      repo = "innoextract_win";
      rev = "e561d8cb6004776eecb3184c0d56b3534a0c7e15";
      hash = "sha256-+XFuDq9ILj0J1e2BYznR8pieANNn1xEA7e1FmadWSb4=";
    };
    patches = [ ];
  });

  # Crack: readme.txt sier "Copy Gaea.Engine.dll to <install-dir>". Vi henter
  # den erstattede motor-dll-en og legger den over app/Gaea.Engine.dll under
  # bygget. Versjonsspesifikk — maa matche src-versjonen.
  crackEngineDll = fetchurl {
    url = "https://aceclan.no/derivations_source/Gaea/crack/Gaea.Engine.dll";
    hash = "sha256-pR8R0zaed9yCeQPC8jwKloS2Ahx77842oGcWr/OlW44=";
  };

  # stagingFull har wine-mono og wine-gecko bundlet, saa wineboot installerer
  # dem uten dialog ved foerste oppstart. WoW64-varianten gir 32-bits stoette
  # uten 32-bits systembiblioteker.
  wine = wineWow64Packages.stagingFull;

  dotnetVersion = "8.0.29";

  # Gaea.runtimeconfig.json krever Microsoft.NETCore.App og
  # Microsoft.WindowsDesktop.App 8.0. Zip-arkivene slipper aa kjoere
  # WiX-installerne inne i prefixen; de pakkes ut over hverandre.
  # Runtime-zipen har hostfxr; desktop-zipen har bare WPF/WinForms-pakken.
  dotnetRuntime = fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/Runtime/${dotnetVersion}/dotnet-runtime-${dotnetVersion}-win-x64.zip";
    hash = "sha256-iuwXjoukUIXgP2iNZDD7GSJwcmWeeUGGsPF5SsWgBNg=";
  };

  dotnetDesktop = fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${dotnetVersion}/windowsdesktop-runtime-${dotnetVersion}-win-x64.zip";
    hash = "sha256-fr8NLHHAu1bRYL5egYoAgc1V6CoQZIFKL6+rAK7IXqg=";
  };

  # Gaea skipper med D3D12 Agility SDK (D3D12Core.dll) og kan velge en
  # D3D12-path. Wines innebygde d3d12 er svak; vkd3d-proton er samme
  # oversetterlag som Proton bruker. nixpkgs-pakken er ELF (.so) og kan
  # ikke overstyre PE-dll-er, saa vi henter den offisielle PE-releasen.
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
    # Samme sjekksum som bootstrapperen selv verifiserer mot.
    hash = "sha256-GtwioEz5r0czhVFrnE6zagnCajFMOP+p4XpFrrv56Ss=";
  };

  nativeBuildInputs = [
    innoextract64
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

    # Crack: erstatt original motor-dll (readme.txt).
    install -Dm644 ${crackEngineDll} $out/share/gaea/app/Gaea.Engine.dll

    unzip -q ${dotnetRuntime} -d $out/share/gaea/dotnet
    unzip -q ${dotnetDesktop} -d $out/share/gaea/dotnet

    tar --zstd -xf ${vkd3dProton} -C .
    install -Dm644 -t $out/share/gaea/vkd3d \
      vkd3d-proton-${vkd3dProtonVersion}/x64/d3d12.dll \
      vkd3d-proton-${vkd3dProtonVersion}/x64/d3d12core.dll

    mkdir icons && (cd icons && icotool -x $out/share/gaea/app/Gaea-2.ico)
    install -Dm644 icons/*_512x512x32.png \
      $out/share/icons/hicolor/512x512/apps/gaea.png

    install -Dm755 ${./launcher.sh} $out/bin/gaea
    substituteInPlace $out/bin/gaea \
      --subst-var out \
      --subst-var-by dxvk ${dxvk.bin}
    wrapProgram $out/bin/gaea \
      --prefix PATH : ${lib.makeBinPath [ wine coreutils ]}

    install -Dm644 ${./gaea.desktop} $out/share/applications/gaea.desktop
    substituteInPlace $out/share/applications/gaea.desktop --subst-var out

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
