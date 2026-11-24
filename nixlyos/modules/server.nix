{ config, lib, ... }:

let
  # Servers never sleep.
  awake = {
    systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: { enable = false; });
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };
  };
in
{
  imports = [ awake ];

  assertions = [{
    assertion = config.nixlyos.mode == "server";
    message = "The server module belongs to profiles on the server platform.";
  }];
}
