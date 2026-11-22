{ lib, callPackage, buildGoModule, makeWrapper, git, nix-eval-jobs, nixfmt, openssh }:

let
  web = callPackage ./web.nix { };
in
buildGoModule {
  pname = "cachepanel";
  version = "0.1.0";
  src = ../server;
  vendorHash = "sha256-HUM/p8WH95LwtcIXuP9//bBVzIrdWf3x7WSBqdDcKMk=";
  env.CGO_ENABLED = 0;
  ldflags = [ "-s" "-w" ];
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git nixfmt openssh ];

  # Nix itself comes from the host.
  postInstall = ''
    wrapProgram $out/bin/cachepanel \
      --set-default CACHEPANEL_WEB_ROOT ${web} \
      --prefix PATH : ${lib.makeBinPath [ git nix-eval-jobs nixfmt openssh ]}
  '';

  passthru = { inherit web; };
  meta.mainProgram = "cachepanel";
}
