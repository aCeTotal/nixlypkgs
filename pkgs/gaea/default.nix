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
  innoextract,
  unzip,
  icoutils,
  makeWrapper,
  coreutils,
  dxvk,
  wineWow64Packages,
}:

let
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
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gaea";
  version = "2.0.6.0";

  src = fetchurl {
    urls = [
      "https://aceclan.no/derivations_source/Gaea/Gaea-${finalAttrs.version}.exe"
      "https://get.gaea.app/Release/Gaea-${finalAttrs.version}.exe"
    ];
    # Samme sjekksum som bootstrapperen selv verifiserer mot.
    hash = "sha256-CsMozYp6pORKVyIGG+cSoP6+oxScMEkScoi5eGkBlK8=";
  };

  nativeBuildInputs = [
    innoextract
    unzip
    icoutils
    makeWrapper
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    innoextract --extract --silent --include app --output-dir . "$src"
    install -d $out/share/gaea
    mv app $out/share/gaea/app

    unzip -q ${dotnetRuntime} -d $out/share/gaea/dotnet
    unzip -q ${dotnetDesktop} -d $out/share/gaea/dotnet

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
