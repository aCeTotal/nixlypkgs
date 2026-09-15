{ pkgs, ... }:

let
  # Version mismatch kills Vulkan decode (0xC0F11312).
  install = pkgs.writeShellScript "geforce-now-install" ''
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak remote-add --if-not-exists geforcenow https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
    flatpak install --noninteractive --or-update geforcenow com.nvidia.geforcenow

    ver=$(sed -n 's/.*Kernel Module *\([0-9][0-9.]*\).*/\1/p' /proc/driver/nvidia/version 2>/dev/null | tr . -)
    if [ -n "$ver" ]; then
      flatpak install --noninteractive --or-update flathub org.freedesktop.Platform.GL.nvidia-$ver
    fi
    flatpak uninstall --noninteractive --unused
  '';

  unit = {
    path = [ pkgs.flatpak pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${install}";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
in
{
  imports = [ ./qos.nix ./slice.nix ./focus.nix ./launch.nix ];

  services.flatpak.enable = true;

  # Installs GFN, pins GL runtime to driver. The condition keeps this off
  # every later boot: a remote check plus flatpak's own IO competed with
  # the session's cold start for nothing once the app is already there.
  systemd.services.geforce-now-install = unit // {
    description = "Install NVIDIA GeForce NOW flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/flatpak/app/com.nvidia.geforcenow";
  };

  # Updates run on their own schedule instead.
  systemd.services.geforce-now-update = unit // {
    description = "Update NVIDIA GeForce NOW flatpak";
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.geforce-now-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = false;
    };
  };
}
