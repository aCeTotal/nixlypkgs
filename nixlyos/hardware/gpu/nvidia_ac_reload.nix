{ pkgs, ... }:

let
  # A charger dropout leaves the driver capped at 10 W until it reloads.
  reload = pkgs.writeShellScript "nvidia-ac-reload" ''
    export PATH=${pkgs.kmod}/bin:${pkgs.coreutils}/bin

    on_mains() {
      for s in /sys/class/power_supply/*; do
        [ "$(cat "$s/type")" = Mains ] && [ "$(cat "$s/online")" = 1 ] && return 0
      done
      return 1
    }

    # Idle when no reference comes from outside the module stack.
    idle() {
      for m in nvidia_drm nvidia_uvm nvidia_modeset nvidia; do
        set -- /sys/module/$m/holders/*
        [ -e "$1" ] || set --
        [ "$(cat /sys/module/$m/refcnt)" -eq $# ] || return 1
      done
    }

    sleep 2
    while on_mains; do
      if idle; then
        modprobe -r nvidia_drm nvidia_uvm nvidia_modeset nvidia
        modprobe nvidia_drm
        modprobe nvidia_uvm
        exit 0
      fi
      sleep 1
    done
  '';
in
{
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start nvidia-ac-reload.service"
  '';

  systemd.services.nvidia-ac-reload = {
    description = "Reload the NVIDIA driver after the charger returns";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = reload;
    };
  };
}
