{ config, pkgs, inputs, lib, nixlyUser, hwData, nixlySelection, ... }:

let
  catalog = import ../lib/catalog-pick.nix { inherit hwData nixlySelection; };
in
{
    imports = catalog.pick "home";

    home = {
    username = nixlyUser;
    homeDirectory = "/home/${nixlyUser}";
    stateVersion = "24.05";
    };
    
    programs.bash.shellAliases = {
      "update" = "nixlyos-update";
      "nixly" = "cd $HOME/.local/nixlyos/";
      "c" = "claude --dangerously-skip-permissions";
      "ai" = "nixly-ai";
    };


    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
          autoconnect = ["qemu:///system"];
          uris = ["qemu:///system"];
     };
    };

    # basePath satisfies the home-manager module defaults.
    accounts.calendar.basePath = ".calendar";
    accounts.contact.basePath = ".contacts";

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    # The login keyring is auto-unlocked via PAM.
    home.file.".local/share/keyrings/default".text = "login";
}
