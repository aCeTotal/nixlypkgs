# Offisiell blender.org-binary for Blender LTS. Bygges ikke fra kilde:
# Blender Foundation distribuerer ferdig kompilerte Cycles-kernels for CUDA
# (.cubin), OptiX (.ptx), HIP og oneAPI. De kan ikke settes sammen fra separate
# cache-pakker etterpaa — GPU-backends er compile-time i Cycles.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  addDriverRunpath,
  alsa-lib,
  dbus,
  libdrm,
  libglvnd,
  libice,
  libjack2,
  libpulseaudio,
  libsm,
  libx11,
  libxcursor,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxt,
  ncurses,
  util-linux,
  wayland,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "blender-bin-lts";
  version = "5.2.0";

  src = fetchurl {
    url = "https://download.blender.org/release/Blender5.2/blender-${finalAttrs.version}-linux-x64.tar.xz";
    # Verifisert mot blender-5.2.0.sha256 fra download.blender.org.
    hash = "sha256-lvbBgaMPSVBgeDnchNQqNUslDYoCMbCYtZt7xpw1HEg=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    addDriverRunpath
  ];

  # Alt av grafikk/render-stack ligger bundlet i tarballens lib/ ($ORIGIN/lib).
  # Kun det Blender forventer fra systemet listes her.
  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib # de fire neste lenkes av bundlet libSDL3
    dbus
    libjack2
    libpulseaudio
    libdrm
    libglvnd # libGL/libEGL/libGLES, lenket av bundlet USD og SDL3
    libice
    libsm
    libx11
    libxcursor
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxt
    ncurses # libncursesw/libpanelw/libtinfo for bundlet python
    util-linux # libuuid, samme
  ];

  # dlopen-es ved kjoretid, saa de maa inn i RUNPATH manuelt.
  runtimeDependencies = [
    alsa-lib
    dbus
    libglvnd
    libjack2
    libpulseaudio
    wayland
  ];

  # libcuda.so.1 / libnvoptix.so.1 kommer fra nvidia-driveren, ikke fra nixpkgs.
  appendRunpaths = [ "${addDriverRunpath.driverLink}/lib" ];

  # Driver-leverte og valgfrie backends finnes ikke i byggemiljoet.
  # libGLES_CM/libsteam_api er valgfrie SDL3-baksider Blender ikke bruker.
  autoPatchelfIgnoreMissingDeps = [
    "libcuda.so.1"
    "libamdhip64.so.7"
    "libze_loader.so.1"
    "libGLES_CM.so.1"
    "libsteam_api.so"
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/blender
    cp -a . $out/share/blender

    mkdir -p $out/bin
    ln -s $out/share/blender/blender $out/bin/blender
    ln -s $out/share/blender/blender-thumbnailer $out/bin/blender-thumbnailer

    install -Dm0644 blender.desktop $out/share/applications/blender.desktop
    install -Dm0644 blender.svg $out/share/icons/hicolor/scalable/apps/blender.svg
    install -Dm0644 blender-symbolic.svg \
      $out/share/icons/hicolor/symbolic/apps/blender-symbolic.svg

    runHook postInstall
  '';

  meta = {
    description = "Blender ${finalAttrs.version} LTS, offisiell binary med CUDA/OptiX/HIP/oneAPI";
    homepage = "https://www.blender.org/";
    license = with lib.licenses; [
      gpl2Plus
      nvidiaCudaRedist # OptiX/CUDA-kernels bundlet av Blender Foundation
    ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "blender";
  };
})
