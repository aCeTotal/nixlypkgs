{ nixlyUser, sshKeys, ... }:

{
  # Installer sets password; sudo only.
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";

  users.users.${nixlyUser} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = sshKeys;
  };

  security.sudo.enable = false;
  security.sudo-rs = {
    enable = true;
    execWheelOnly = true;
  };
}
