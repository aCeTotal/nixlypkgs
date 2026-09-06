{ config, pkgs, inputs, lib, nixlyUser, ... }:

{

    imports = [
      # No user/steam.nix: its wildcard CompatToolMapping at priority 250 broke
      # the Steam Linux Runtime, and autoconfig.nix now owns all Steam config.
      ./blender_setup.nix
      # programs
      ./git.nix
      ./bash.nix
      ./btop.nix
      ./starship.nix
      ./alacritty.nix
      ./nixlytile.nix
      ./env.nix
      ./gtk.nix
      ./qt.nix
      ./emulator_config.nix
      ./audio_priority.nix
      ./emulator_playlists.nix
      ./caveman.nix
      ./claude.nix
      ./discord_rpc.nix
    ];

    home = {
    username = nixlyUser;
    homeDirectory = "/home/${nixlyUser}";
    stateVersion = "24.05";
    };
    
    programs.bash.shellAliases = {
      "update" = "nixlyos-update";
      "channel" = "nixlyos-channel";
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
