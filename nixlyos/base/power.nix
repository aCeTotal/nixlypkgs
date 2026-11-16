{ pkgs, lib, nixlyUser, ... }:

{
  # logind owns lid and power keys.
  services.acpid.enable = lib.mkForce false;

  # nixlytile owns these power knobs (no power-profiles-daemon); grant users write.
  systemd.services.platform-profile-perms = {
    description = "Make power/clock/backlight sysfs files writable for the users group";
    wantedBy = [ "multi-user.target" ];
    # msi-ec loads via its own autoload service — shift_mode must exist
    # before the perms pass runs
    after = [ "msi-ec-autoload.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "platform-profile-perms" ''
        for f in /sys/firmware/acpi/platform_profile \
                 /sys/devices/platform/msi-ec/shift_mode \
                 /sys/devices/system/cpu/intel_pstate/no_turbo \
                 /sys/devices/system/cpu/cpufreq/boost \
                 /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq \
                 /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq \
                 /sys/class/power_supply/BAT*/charge_control_start_threshold \
                 /sys/class/power_supply/BAT*/charge_control_end_threshold \
                 /sys/class/backlight/*/brightness; do
          if [ -e "$f" ]; then
            ${pkgs.coreutils}/bin/chgrp users "$f"
            ${pkgs.coreutils}/bin/chmod 0664 "$f"
          fi
        done
      '';
    };
  };

  # Let total reboot and power off without a password, even from sessions that
  # are not active on a seat.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.login1.reboot" ||
           action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
           action.id == "org.freedesktop.login1.power-off" ||
           action.id == "org.freedesktop.login1.power-off-multiple-sessions") &&
          subject.user == "${nixlyUser}") {
        return polkit.Result.YES;
      }
    });
  '';
}
