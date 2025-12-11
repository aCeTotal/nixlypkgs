{ lib
, stdenv
, fetchurl
, makeWrapper
, electron
, freerdp3
, usbutils
, libusb1
, hwdata
}:

stdenv.mkDerivation rec {
  pname = "winboat";
  # Match source and sha used in the provided flake
  version = "0.8.5";

  src = fetchurl {
    url = "https://github.com/aCeTotal/winboat/releases/download/v${version}/winboat-${version}-x64.tar.gz";
    # Hash provided in the prompt; ensure it matches the chosen version
    sha256 = "1mvvd6y0wcpqh6wmjzpax7pkdpwcibhb9y7hnrd7x79fr0s5f3mp";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ electron ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/winboat $out/bin
    # Copy all extracted release contents into share/winboat
    (cd . && tar cf - .) | (cd $out/share/winboat && tar xf -)

    # Launch wrapper: run the Electron binary with the bundled app.asar
    cat > $out/bin/winboat <<EOF
#!/usr/bin/env bash
exec ${electron}/bin/electron "$out/share/winboat/resources/app.asar" "$@"
EOF
    chmod +x $out/bin/winboat

    # Desktop entry
    mkdir -p $out/share/applications
    cat > $out/share/applications/winboat.desktop <<EOF
[Desktop Entry]
Name=WinBoat
Exec=$out/bin/winboat %U
Type=Application
Terminal=false
Icon=winboat
Categories=Utility;
EOF

    # Icons (best-effort if present in the release)
    mkdir -p $out/share/icons/hicolor/256x256/apps
    if [ -f icons/icon.png ]; then
      cp icons/icon.png $out/share/icons/hicolor/256x256/apps/winboat.png
      mkdir -p $out/share/winboat
      cp icons/icon.png $out/share/winboat/icon.png
    elif [ -f resources/icon.png ]; then
      cp resources/icon.png $out/share/icons/hicolor/256x256/apps/winboat.png
      mkdir -p $out/share/winboat
      cp resources/icon.png $out/share/winboat/icon.png
    fi

    # Data files: provide usb.ids from hwdata
    mkdir -p $out/share/winboat/data
    mkdir -p $out/share/winboat/resources/data
    cp ${hwdata}/share/hwdata/usb.ids $out/share/winboat/data/usb.ids
    cp ${hwdata}/share/hwdata/usb.ids $out/share/winboat/resources/data/usb.ids

    # Guest server payload (location differs between releases)
    mkdir -p $out/lib/guest_server
    if [ -d guest_server ]; then
      mkdir -p $out/share/winboat/resources/guest_server
      cp -a guest_server/. $out/share/winboat/resources/guest_server/
      cp -a guest_server/. $out/share/winboat/guest_server/
      cp -a guest_server/. $out/lib/guest_server/
    elif [ -d resources/guest_server ]; then
      mkdir -p $out/share/winboat/resources/guest_server
      cp -a resources/guest_server/. $out/share/winboat/resources/guest_server/
      cp -a resources/guest_server/. $out/share/winboat/guest_server/
      cp -a resources/guest_server/. $out/lib/guest_server/
    else
      echo "warning: guest_server directory not found in source"
    fi

    runHook postInstall
  '';

  postFixup = ''
    # Ensure required tools and libraries are available at runtime
    wrapProgram "$out/bin/winboat" \
      --prefix PATH : ${lib.makeBinPath [ freerdp3 usbutils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ electron libusb1 (lib.getLib stdenv.cc.cc) ]}
  '';

  meta = with lib; {
    description = "WinBoat - Run Windows apps on Linux with seamless integration";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    homepage = "https://github.com/aCeTotal/winboat";
    mainProgram = "winboat";
  };
}
