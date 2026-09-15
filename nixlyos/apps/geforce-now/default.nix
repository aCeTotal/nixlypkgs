{ pkgs, ... }:

{
  imports = [ ./qos.nix ];

  services.flatpak.enable = true;

  # Installs GFN, pins GL runtime to driver.
  systemd.services.geforce-now-install = {
    description = "Install NVIDIA GeForce NOW flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak remote-add --if-not-exists geforcenow https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
      flatpak install --noninteractive --or-update geforcenow com.nvidia.geforcenow

      # Version mismatch kills Vulkan decode (0xC0F11312).
      ver=$(sed -n 's/.*Kernel Module *\([0-9][0-9.]*\).*/\1/p' /proc/driver/nvidia/version 2>/dev/null | tr . -)
      if [ -n "$ver" ]; then
        flatpak install --noninteractive --or-update flathub org.freedesktop.Platform.GL.nvidia-$ver
      fi
      flatpak uninstall --noninteractive --unused
    '';
  };
}
