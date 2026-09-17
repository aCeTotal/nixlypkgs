{ pkgs, ... }:

let
  triage = pkgs.writeShellApplication {
    name = "nixly-dltriage";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = builtins.readFile ./triage.sh;
  };
in
{
  # Verdicts are acted on here, not by clamonacc.
  systemd.services.nixly-dltriage = {
    description = "Triage quarantined downloads";
    after = [ "clamav-clamonacc.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${triage}/bin/nixly-dltriage";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
