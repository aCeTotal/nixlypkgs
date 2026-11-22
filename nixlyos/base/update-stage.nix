# Stages the next generation while idle.
{ pkgs, nixlyUser, ... }:

let
  stage = pkgs.writeShellApplication {
    name = "nixlyos-stage";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.gawk (import ../lib/panel-cli.nix { inherit pkgs; }) ];
    text = builtins.readFile ../scripts/stage.sh;
  };
in
{
  environment.systemPackages = [ stage ];

  systemd.services.nixlyos-stage = {
    description = "Stage the next NixlyOS generation in the background";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = nixlyUser;
      ExecStart = "${stage}/bin/nixlyos-stage";
      # Invisible to the session.
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.nixlyos-stage = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "1min";
      Persistent = true;
    };
  };
}
