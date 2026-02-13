{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  wrapGAppsHook3,

  # Core libraries
  alsa-lib,
  atk,
  cacert,
  cairo,
  dconf,
  enchant,
  file,
  fontconfig,
  freetype,
  fuse3,
  gdk-pixbuf,
  glib,
  glib-networking,
  gnome2,
  gtk2,
  gtk2-x11,
  gtk3,
  gtk_engines,
  harfbuzzFull,
  heimdal,
  hyphen,
  krb5,
  lcms2,
  libGL,
  libappindicator-gtk3,
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
  sane-backends,
  speex,
  symlinkJoin,
  systemd,
  tzdata,
  which,
  woff2,
  zlib,

  # X11 libraries
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

  # Wayland support
  wayland,
  libxkbcommon,

  # MIME & XDG support
  shared-mime-info,
  desktop-file-utils,
  xdg-utils,

  extraCerts ? [ ],
}:

let
  version = "25.08.10.111";
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
    url = "https://pfoprod.ddns.net/Adrian/linuxx64-${version}.tar.gz";
    hash = "sha256-bd3ClxBRJgvjJW+waKBE31k9ePam+n2pHeSjlkvkDRo=";
    curlOptsList = [ "--insecure" ];
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
          --set GDK_BACKEND "wayland" \
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

      # Run upstream installer
      sed -i \
        -e 's,^ANSWER="",ANSWER="$INSTALLER_YES",g' \
        -e 's,/bin/true,true,g' \
        -e 's, -C / , -C . ,g' \
        ./linuxx64/hinst
      source_date=$(date --utc --date=@$SOURCE_DATE_EPOCH "+%F %T")
      faketime -f "$source_date" ${stdenv.shell} linuxx64/hinst CDROM "$(pwd)"

      # Setlog utility
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

      ln -sf $ICAInstDir/util/storebrowse $out/bin/storebrowse

      # --- Security certificates ---
      echo "Expanding certificates..."
      pushd "$ICAInstDir/keystore/cacerts"
      awk 'BEGIN {c=0;} /BEGIN CERT/{c++} { print > "cert." c ".pem"}' \
        < ${cacert}/etc/ssl/certs/ca-bundle.crt
      popd
      ${mkWrappers copyCert extraCerts}

      # --- Gstreamer 1.0 only ---
      rm $ICAInstDir/util/{gst_aud_{play,read},gst_*0.10,libgstflatstm0.10.so} || true
      ln -sf $ICAInstDir/util/gst_play1.0 $ICAInstDir/util/gst_play
      ln -sf $ICAInstDir/util/gst_read1.0 $ICAInstDir/util/gst_read

      # --- Timezone ---
      echo UTC > "$ICAInstDir/timezone"

      # --- MIME type for .ica files ---
      cat > $out/share/mime/packages/citrix-workspace.xml << 'MIME'
      <?xml version="1.0" encoding="UTF-8"?>
      <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-spec">
        <mime-type type="application/x-ica">
          <comment>Citrix ICA Connection File</comment>
          <glob pattern="*.ica"/>
        </mime-type>
      </mime-info>
      MIME

      # --- Desktop files ---
      cp $ICAInstDir/desktop/* $out/share/applications/ || true

      # Create a dedicated wfica desktop file that handles .ica files
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

      # Remove MimeType from selfservice desktop to avoid it hijacking .ica files
      for f in $out/share/applications/*.desktop; do
        case "$(basename "$f")" in
          wfica.desktop) ;; # skip, we just created it
          *) sed -i '/^MimeType=.*application\/x-ica/d' "$f" ;;
        esac
      done
      update-desktop-database $out/share/applications || true

      # --- Client Drive Mapping (CDM) – Linux filesystem access ---
      # module.ini: load the CDM virtual-channel driver
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

      # wfclient.ini: inject drive mappings into the [WFClient] section
      if [ -f "$ICAInstDir/config/wfclient.ini" ]; then
        if ! grep -q "CDMAllowed" "$ICAInstDir/config/wfclient.ini"; then
          sed -i '/^\[WFClient\]/a\
CDMAllowed=True\
DriveEnabledA=True\
DrivePathA=\/\
DriveReadAccessA=3\
DriveWriteAccessA=3\
DriveEnabledH=True\
DrivePathH=$HOME\/\
DriveReadAccessH=3\
DriveWriteAccessH=3' "$ICAInstDir/config/wfclient.ini"
        fi
      fi

      # --- Disable TWI (graphics settings live in All_Regions.ini) ---
      if [ -f "$ICAInstDir/config/wfclient.ini" ]; then
        if ! grep -q "TWIMode" "$ICAInstDir/config/wfclient.ini"; then
          cat >> "$ICAInstDir/config/wfclient.ini" << 'BASIC'

      TWIMode=0
      BASIC
        fi
      fi

      # Seamless Windows, CDM & Thinwire Graphics – All_Regions.ini
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
      TWGFX
        fi
      fi

      # module.ini – disable TWI
      if [ -f "$ICAInstDir/config/module.ini" ]; then
        if ! grep -q "\[ICA 3.0\]" "$ICAInstDir/config/module.ini"; then
          cat >> "$ICAInstDir/config/module.ini" << 'ICA30'

      [ICA 3.0]
      TWIMode=0
      ICA30
        fi
      fi

      echo $src >> "$out/share/workspace_dependencies.pin"

      runHook postInstall
    '';

  # autoPatchelf must run before ctx_rehash
  dontAutoPatchelf = true;

  postFixup = ''
    # Null out hardcoded webkit bundle path so it falls back to LD_LIBRARY_PATH
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
