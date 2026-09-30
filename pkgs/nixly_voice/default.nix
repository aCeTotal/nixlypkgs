{ lib
, stdenv
, fetchurl
, src
, meson
, ninja
, pkg-config
, whisper-cpp-vulkan
, pipewire
}:

let
  whisperModel = fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin";
    hash = "sha256-MX62nBFnPJ3h4fDUWbJTmZgE7HGsTCPBfs9fviTiWaE=";
  };
  vadModel = fetchurl {
    url = "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v6.2.0.bin";
    hash = "sha256-KqJpt4XutTqCmDogUB3ffB2cSOM6tjpBORrGyff7aYc=";
  };
in
stdenv.mkDerivation {
  pname = "nixly-voice";
  version = "0.1";

  inherit src;

  strictDeps = true;
  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ whisper-cpp-vulkan pipewire ];

  mesonFlags = [
    "-Dwhisper_model=${whisperModel}"
    "-Dvad_model=${vadModel}"
  ];
  doCheck = true;

  meta = {
    description = "Instant offline voice commands for nixlytile";
    homepage = "https://github.com/aCeTotal/nixly_voice";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "nixly-voice";
  };
}
