{ pkgs, ... }:

{
  imports = [ ./qos.nix ];

  services.flatpak.enable = true;

  # Mirrors what NVIDIA's GeForceNOWSetup.bin installer does: add flathub
  # (needed for the org.freedesktop.Platform.GL.nvidia-* driver runtimes),
  # add NVIDIA's GeForce NOW remote, then install/update the app. The
  # flatpak's own exported desktop file is the only launcher entry.
  systemd.services.geforce-now-install = {
    description = "Install NVIDIA GeForce NOW flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak remote-add --if-not-exists geforcenow https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
      flatpak install --noninteractive --or-update geforcenow com.nvidia.geforcenow
    '';
  };
}
