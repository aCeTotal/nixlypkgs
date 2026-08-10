{ config, lib, pkgs, ... }:

let
  cfg = config.programs.citrix-workspace-nixly;
in
{
  options.programs.citrix-workspace-nixly = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable Citrix Workspace (Nixly). Installs the package and registers
        wfica as the default handler for .ica files (application/x-ica),
        so opening an .ica file launches a Citrix session automatically.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.citrix-workspace-nixly;
      description = "The citrix-workspace-nixly package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    xdg.mime = {
      enable = true;
      addedAssociations."application/x-ica" = "wfica.desktop";
      defaultApplications."application/x-ica" = "wfica.desktop";
    };
  };
}
