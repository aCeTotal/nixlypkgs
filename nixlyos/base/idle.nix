{ lib, ... }:

{
  # nixly-idled locks; laptop lids hibernate (hibernate.nix).
  services.logind.settings.Login = {
    IdleAction = "ignore";
    IdleActionSec = 0;
    HandleLidSwitch = lib.mkDefault "suspend";
    HandleLidSwitchExternalPower = lib.mkDefault "suspend";
    HandleLidSwitchDocked = "ignore";
  };
}
