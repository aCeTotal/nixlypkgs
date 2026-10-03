# No GUI; panel only.
{ ... }:

{
  fonts.fontconfig.enable = false;
  services.udisks2.enable = false;
  boot.enableContainers = false;
  hardware.enableRedistributableFirmware = true;

  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=1G
    MaxRetentionSec=3month
  '';
}
