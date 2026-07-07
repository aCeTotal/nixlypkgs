# GLM – ZCode + lokal GLM-4.7-Flash via llama.cpp med automatisk GPU-bruk.
{ lib, symlinkJoin, callPackage }:

let
  zcode = callPackage ./zcode.nix { };
  glm-server = callPackage ./server.nix { };
  glm = callPackage ./launcher.nix { inherit zcode glm-server; };
in
symlinkJoin {
  name = "glm";
  paths = [ glm glm-server zcode ];

  passthru = { inherit zcode glm-server; };

  meta = {
    description = "GLM coding stack: ZCode + local GLM-4.7-Flash (llama.cpp, auto-GPU)";
    homepage = "https://z.ai";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "glm";
  };
}
