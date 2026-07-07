# ZCode – official Z.ai agentic coding desktop app (Linux AppImage)
{ lib, stdenv, appimageTools, fetchurl }:

let
  pname = "zcode";
  version = "3.3.0";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/ZCode-${version}-linux-x64.AppImage";
      sha256 = "00c5ffedc1cf48d1c26a27d979047e30bc8388ca067e39dfd4845fa8f772df79";
    };
    aarch64-linux = fetchurl {
      url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/ZCode-${version}-linux-arm64.AppImage";
      sha256 = "b2afaa36b2ede103417c58be0b87e9ffe41098eb50c6a0a5333fbab3fa7e311f";
    };
  };

  src = sources.${stdenv.hostPlatform.system};

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    if [ -f ${contents}/zcode.desktop ]; then
      install -Dm444 ${contents}/zcode.desktop $out/share/applications/zcode.desktop
      substituteInPlace $out/share/applications/zcode.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=zcode'
    fi
    for icon in ${contents}/usr/share/icons/hicolor/512x512/apps/*.png ${contents}/zcode.png; do
      if [ -f "$icon" ]; then
        install -Dm444 "$icon" $out/share/icons/hicolor/512x512/apps/zcode.png
        break
      fi
    done
  '';

  meta = {
    description = "Official Z.ai agentic development environment for GLM models";
    homepage = "https://zcode.z.ai";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "zcode";
  };
}
