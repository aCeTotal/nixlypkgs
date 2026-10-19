# Keeps ~/git flakes through nix-gc.
{ pkgs, nixlyUser, ... }:

let
  projectRoots = pkgs.writeShellApplication {
    name = "nixly-project-roots";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.jq ];
    text = builtins.readFile ../scripts/project-roots.sh;
  };
in
{
  systemd.services.nixly-project-roots = {
    description = "GC-root every flake in ~/git";
    serviceConfig = {
      Type = "oneshot";
      User = nixlyUser;
      ExecStart = "${projectRoots}/bin/nixly-project-roots";
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };

  systemd.services.nix-gc = {
    requires = [ "nixly-project-roots.service" ];
    after = [ "nixly-project-roots.service" ];
  };
}
