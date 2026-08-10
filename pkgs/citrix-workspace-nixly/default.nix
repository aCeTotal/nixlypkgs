{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  wrapGAppsHook3,

  alsa-lib,
  atk,
  cacert,
  cairo,
  coreutils,
  curl,
  dconf,
  enchant,
  file,
  fontconfig,
  freetype,
  fuse3,
  gdk-pixbuf,
  glib,
  glib-networking,
  gnugrep,
  gnused,
  gnome2,
  gtk2,
  gtk2-x11,
  gtk3,
  gtk_engines,
  harfbuzzFull,
  heimdal,
  hyphen,
  gpgme,
  krb5,
  lcms2,
  libproxy,
  networkmanager,
  util-linux,
  libGL,
  libappindicator-gtk3,
  libayatana-appindicator,
  libcanberra-gtk3,
  libcap,
  libcxx,
  libfaketime,
  libgbm,
  libinput,
  libjpeg8,
  libjson,
  libmanette,
  libnotify,
  libpng12,
  libpulseaudio,
  libredirect,
  libseccomp,
  libsecret,
  libsoup_2_4,
  libvorbis,
  libxml2_13,
  libxslt,
  llvmPackages,
  more,
  nspr,
  nss,
  opencv4,
  openssl,
  pango,
  pcsclite,
  perl,
  pugixml,
  webkitgtk_4_1,
  sane-backends,
  speex,
  symlinkJoin,
  systemd,
  tzdata,
  which,
  woff2,
  zlib,

  libxtst,
  libxscrnsaver,
  libxrender,
  libxmu,
  libxinerama,
  libxfixes,
  libxext,
  libxaw,
  libx11,
  xprop,
  xdpyinfo,
  libxcb,

  wayland,
  libxkbcommon,

  shared-mime-info,
  desktop-file-utils,
  xdg-utils,

  extraCerts ? [ ],
}:

let
  version = "26.04.0.105";
  homepage = "https://www.citrix.com/downloads/workspace-app/linux/workspace-app-for-linux-latest.html";

  fuse3' = symlinkJoin {
    name = "fuse3-backwards-compat";
    paths = [ (lib.getLib fuse3) ];
    postBuild = ''
      for so in $out/lib/libfuse3.so.3.*; do
        ln -sf "$so" $out/lib/libfuse3.so.3
        break
      done
    '';
  };

  openssl' = symlinkJoin {
    name = "openssl-backwards-compat";
    nativeBuildInputs = [ makeWrapper ];
    paths = [ (lib.getLib openssl) ];
    postBuild = ''
      ln -sf $out/lib/libcrypto.so $out/lib/libcrypto.so.1.0.0
      ln -sf $out/lib/libssl.so $out/lib/libssl.so.1.0.0
    '';
  };

  opencv4' = symlinkJoin {
    name = "opencv4-compat";
    nativeBuildInputs = [ makeWrapper ];
    paths = [ opencv4 ];
    postBuild = ''
      for so in ${opencv4}/lib/*.so; do
        ln -s "$so" $out/lib/$(basename "$so").407 || true
        ln -s "$so" $out/lib/$(basename "$so").410 || true
      done
    '';
  };

in

stdenv.mkDerivation {
  pname = "citrix-workspace-nixly";
  inherit version;

  src = fetchurl {
    url = "https://aceclan.no/derivations_source/citrix/workspace/linuxx64-gcc-8-${version}.tar.gz";
    hash = "sha256-r+xwNiCbMiP1VsHvHKhK2iREhFTvE4gP9ljoSjWIGKs=";
  };

  dontBuild = true;
  dontConfigure = true;
  sourceRoot = ".";
  preferLocalBuild = true;
  passthru.icaroot = "${placeholder "out"}/opt/citrix-icaclient";

  nativeBuildInputs = [
    autoPatchelfHook
    desktop-file-utils
    file
    libfaketime
    makeWrapper
    more
    which
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    atk
    cairo
    dconf
    enchant
    fontconfig
    freetype
    fuse3'
    gdk-pixbuf
    glib-networking
    gnome2.gtkglext
    gtk2
    gtk2-x11
    gtk3
    gtk_engines
    harfbuzzFull
    heimdal
    hyphen
    krb5
    lcms2
    libGL
    libcanberra-gtk3
    libcap
    libcxx
    libgbm
    libinput
    libjpeg8
    libjson
    libmanette
    libnotify
    libpng12
    libpulseaudio
    libseccomp
    libsecret
    libsoup_2_4
    libvorbis
    libxml2_13
    libxslt
    llvmPackages.libunwind
    nspr
    nss
    opencv4'
    openssl'
    pango
    pcsclite
    (pugixml.override { shared = true; })
    webkitgtk_4_1
    libayatana-appindicator
    curl
    gpgme
    libproxy
    networkmanager
    (lib.getLib util-linux)
    libx11
    sane-backends
    shared-mime-info
    speex
    stdenv.cc.cc
    (lib.getLib systemd)
    wayland
    woff2
    libxkbcommon
    libxscrnsaver
    libxaw
    libxmu
    libxtst
    zlib
  ];

  runtimeDependencies = [
    glib
    glib-networking
    libappindicator-gtk3
    libGL
    pcsclite
    wayland
    libxkbcommon

    libx11
    libxscrnsaver
    libxext
    libxfixes
    libxinerama
    libxmu
    libxrender
    libxtst
    libxcb
    xdpyinfo
    xprop
  ];

  installPhase =
    let
      icaFlag =
        program:
        if (builtins.match "selfservice(.*)" program) != null then
          "--icaroot"
        else if (builtins.match "wfica(.*)" program != null) then
          null
        else
          "-icaroot";

      wrap = program: ''
        wrapProgram $out/opt/citrix-icaclient/${program} \
          ${lib.optionalString (icaFlag program != null) ''--add-flags "${icaFlag program} $ICAInstDir"''} \
          --set ICAROOT "$ICAInstDir" \
          --set GDK_BACKEND "x11" \
          --prefix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules" \
          --prefix XDG_DATA_DIRS : "${shared-mime-info}/share" \
          --prefix PATH : "${lib.makeBinPath [ xdg-utils xprop xdpyinfo ]}" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ wayland libxkbcommon fuse3 ]}:$ICAInstDir:$ICAInstDir/lib:$ICAInstDir/usr/lib/x86_64-linux-gnu:$ICAInstDir/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/injected-bundle" \
          --set LD_PRELOAD "${libredirect}/lib/libredirect.so ${lib.getLib pcsclite}/lib/libpcsclite.so" \
          --set NIX_REDIRECTS "/usr/share/zoneinfo=${tzdata}/share/zoneinfo:/etc/zoneinfo=${tzdata}/share/zoneinfo:/etc/timezone=$ICAInstDir/timezone:/usr/lib/x86_64-linux-gnu=$ICAInstDir/usr/lib/x86_64-linux-gnu"
      '';

      wrapLink = program: ''
        ${wrap program}
        ln -sf $out/opt/citrix-icaclient/${program} $out/bin/${baseNameOf program}
      '';

      copyCert = path: ''
        cp -v ${path} $out/opt/citrix-icaclient/keystore/cacerts/${baseNameOf path}
      '';

      mkWrappers = lib.concatMapStringsSep "\n";

      toWrap = [
        "wfica"
        "selfservice"
        "util/configmgr"
        "util/conncenter"
        "util/ctx_rehash"
      ];
    in
    ''
      runHook preInstall

      mkdir -p $out/{bin,share/applications,share/mime/packages}
      export ICAInstDir="$out/opt/citrix-icaclient"
      export HOME=$(mktemp -d)

      sed -i \
        -e 's,^ANSWER="",ANSWER="$INSTALLER_YES",g' \
        -e 's,/bin/true,true,g' \
        -e 's, -C / , -C . ,g' \
        ./linuxx64/hinst
      source_date=$(date --utc --date=@$SOURCE_DATE_EPOCH "+%F %T")
      faketime -f "$source_date" ${stdenv.shell} linuxx64/hinst CDROM "$(pwd)"

      if [ ! -e "$ICAInstDir/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37.56.4" ]; then
        tar xzf linuxx64/linuxx64.cor/Webkit2gtk4.0/webkit2gtk-4.0.tar.gz \
          --strip-components=1 -C "$ICAInstDir"
      fi

      if [ -f "$ICAInstDir/util/setlog" ]; then
        chmod +x "$ICAInstDir/util/setlog"
        ln -sf "$ICAInstDir/util/setlog" "$out/bin/citrix-setlog"
      fi

      ${mkWrappers wrapLink toWrap}
      ${mkWrappers wrap [
        "PrimaryAuthManager"
        "ServiceRecord"
        "AuthManagerDaemon"
        "util/ctxwebhelper"
      ]}

      rm -f $out/bin/wfica
      substitute ${./wfica-launch.sh} $out/bin/wfica \
        --replace-fail '@wfica@' "$ICAInstDir/wfica" \
        --replace-fail '@coreutils@' "${lib.getBin coreutils}/bin" \
        --replace-fail '@gnused@' "${lib.getBin gnused}/bin" \
        --replace-fail '@gnugrep@' "${lib.getBin gnugrep}/bin"
      chmod +x $out/bin/wfica

      ln -sf $ICAInstDir/util/storebrowse $out/bin/storebrowse

      echo "Expanding certificates..."
      pushd "$ICAInstDir/keystore/cacerts"
      awk 'BEGIN {c=0;} /BEGIN CERT/{c++} { print > "cert." c ".pem"}' \
        < ${cacert}/etc/ssl/certs/ca-bundle.crt
      popd
      ${mkWrappers copyCert extraCerts}

      rm $ICAInstDir/util/{gst_aud_{play,read},gst_*0.10,libgstflatstm0.10.so} || true
      ln -sf $ICAInstDir/util/gst_play1.0 $ICAInstDir/util/gst_play
      ln -sf $ICAInstDir/util/gst_read1.0 $ICAInstDir/util/gst_read

      echo UTC > "$ICAInstDir/timezone"

      cat > $out/share/mime/packages/citrix-workspace.xml << 'MIME'
      <?xml version="1.0" encoding="UTF-8"?>
      <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-spec">
        <mime-type type="application/x-ica">
          <comment>Citrix ICA Connection File</comment>
          <glob pattern="*.ica"/>
        </mime-type>
      </mime-info>
      MIME

      cp $ICAInstDir/desktop/* $out/share/applications/ || true

      cat > $out/share/applications/wfica.desktop << DESKTOP
      [Desktop Entry]
      Name=Citrix Workspace
      Comment=Launch Citrix ICA sessions
      Exec=$out/bin/wfica %f
      Terminal=false
      Type=Application
      MimeType=application/x-ica;
      Categories=Network;
      Icon=$ICAInstDir/icons/000_Internal-Receiver.png
      StartupNotify=true
      DESKTOP

      for f in $out/share/applications/*.desktop; do
        case "$(basename "$f")" in
          wfica.desktop) ;;
          *) sed -i '/^MimeType=.*application\/x-ica/d' "$f" ;;
        esac
      done
      update-desktop-database $out/share/applications || true

      chmod -R u+w "$ICAInstDir/config/" || true

      if [ -f "$ICAInstDir/config/module.ini" ]; then
        if grep -q "\[ClientDrive\]" "$ICAInstDir/config/module.ini"; then
          sed -i '/\[ClientDrive\]/,/^\[/ {
            s/^CDMAllowed=.*/CDMAllowed=True/
          }' "$ICAInstDir/config/module.ini"
        else
          cat >> "$ICAInstDir/config/module.ini" << 'CDM'

      [ClientDrive]
      DriverName=VDCDM.DLL
      CDMAllowed=True
      CDM
        fi
      fi

      for wfc in "$ICAInstDir/config/wfclient.ini" "$ICAInstDir/config/wfclient.template"; do
        [ -f "$wfc" ] || continue
        if ! grep -q "DriveEnabledA" "$wfc"; then
          sed -i '/^\[WFClient\]/a\CDMAllowed=True\nDriveEnabledA=True\nDrivePathA=/\nDriveReadAccessA=3\nDriveWriteAccessA=3' "$wfc"
        fi
        if ! grep -q "^H264Enabled" "$wfc"; then
          sed -i '/^\[WFClient\]/a\H264Enabled=True\nH265Enabled=True\nGraphicsAcceleration=True\nEnableHardwareDecoding=True\nMaximumCompression=True' "$wfc"
        fi
        if ! grep -q "TWIMode" "$wfc"; then
          sed -i '/^\[WFClient\]/a\TWIMode=0' "$wfc"
        fi
      done

      if [ -f "$ICAInstDir/config/All_Regions.ini" ]; then
        if ! grep -q "\[Virtual Channels\\\\Seamless Windows\]" "$ICAInstDir/config/All_Regions.ini"; then
          cat >> "$ICAInstDir/config/All_Regions.ini" << 'SEAMLESS'

      [Virtual Channels\Seamless Windows]
      TWIMode=0
      SEAMLESS
        fi

        if ! grep -q "\[Virtual Channels\\\\Client Drive Mapping\]" "$ICAInstDir/config/All_Regions.ini"; then
          cat >> "$ICAInstDir/config/All_Regions.ini" << 'CDMREG'

      [Virtual Channels\Client Drive Mapping]
      CDMAllowed=True
      CDMREG
        fi

        if ! grep -q "\[Virtual Channels\\\\Thinwire Graphics\]" "$ICAInstDir/config/All_Regions.ini"; then
          cat >> "$ICAInstDir/config/All_Regions.ini" << 'TWGFX'

      [Virtual Channels\Thinwire Graphics]
      DesiredColor=*
      ApproximateColors=*
      DesiredHRES=*
      DesiredVRES=*
      ScreenPercent=0
      UseFullScreen=false
      TWIFullScreenMode=false
      NoWindowManager=false
      H264Enabled=True
      H265Enabled=True
      HardwareEncodeEnabled=True
      DeepCompressionV2Allowed=True
      TWGFX
        fi

        if ! grep -q "\[Network\\\\TCP-IP\\\\HDXEnlightenedDataTransport\]" "$ICAInstDir/config/All_Regions.ini"; then
          cat >> "$ICAInstDir/config/All_Regions.ini" << 'EDT'

      [Network\TCP-IP\HDXEnlightenedDataTransport]
      EDT=Allow
      HDXoverUDP=Preferred
      EDTUseAdaptiveCwnd=True
      EDT
        fi
      fi

      if [ -f "$ICAInstDir/config/module.ini" ]; then
        if grep -q "^\[ICA 3.0\]" "$ICAInstDir/config/module.ini"; then
          if ! grep -q "^TWIMode=" "$ICAInstDir/config/module.ini"; then
            sed -i '/^\[ICA 3.0\]/a\TWIMode=0' "$ICAInstDir/config/module.ini"
          fi
          if ! grep -q "^TransparentKeyPassthrough=" "$ICAInstDir/config/module.ini"; then
            sed -i '/^\[ICA 3.0\]/a\TransparentKeyPassthrough=Local' "$ICAInstDir/config/module.ini"
          fi
        else
          cat >> "$ICAInstDir/config/module.ini" << 'ICA30'

      [ICA 3.0]
      TWIMode=0
      TransparentKeyPassthrough=Local
      ICA30
        fi
      fi

      echo $src >> "$out/share/workspace_dependencies.pin"

      runHook postInstall
    '';

  dontAutoPatchelf = true;
  autoPatchelfIgnoreMissingDeps = [ "libgpgme.so.11" ];

  postFixup = ''
    ${lib.getExe perl} -0777 -pi -e 's{/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/injected-bundle/}{"\0" x length($&)}e' \
      $out/opt/citrix-icaclient/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37.56.4

    autoPatchelf -- "$out"

    $out/opt/citrix-icaclient/util/ctx_rehash
  '';

  meta = {
    license = lib.licenses.unfree;
    description = "Citrix Workspace (Nixly) – with Wayland, MIME & CDM support";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "wfica";
    inherit homepage;
  };
}
