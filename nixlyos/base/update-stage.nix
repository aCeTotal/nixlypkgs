# Background staging of the next system generation — the piece stock NixOS
# lacks: updates are downloaded and built silently while the machine is idle,
# so nixlyos-update usually only has to activate. The staged build sits behind
# a GC root in ~/.local/state/nixlyos/stage and is verified by content key
# before use, never trusted blindly.
{ pkgs, lib, nixlyUser, ... }:

let
  stage = pkgs.writeShellApplication {
    name = "nixlyos-stage";
    runtimeInputs = [ pkgs.coreutils pkgs.nix pkgs.gawk ];
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
      # Invisible to the session: idle CPU/IO scheduling, lowest niceness.
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.nixlyos-stage = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };
}
