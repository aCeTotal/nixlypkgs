{ config, pkgs, lib, nixlyUser, ... }:

{
  users.mutableUsers = true;

  users.users.${nixlyUser} = {
    isNormalUser = true;
    description = "Primary user";
    home = "/home/${nixlyUser}";
    shell = pkgs.bashInteractive;
    initialPassword = "nixly";
    extraGroups = [
      "wheel"
      "bluetooth"
      "disk"
      "power"
      "video"
      "audio"
      "render"
      "systemd-journal"
      "dialout"
      "libvirtd"
      "kvm"
      "input"
      "uinput"
      "gamemode"
      # wpa_supplicant control socket (nixpkgs fixed the group; the old
      # userControlled.group option is gone).
      "wpa_supplicant"
    ];
    openssh.authorizedKeys.keys = [];
  };

  users.groups.uinput = {};
}
