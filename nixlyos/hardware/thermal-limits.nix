{ pkgs, ... }:

let
  # Throttle at 90 °C; acpitz kills power at 100.
  tccOffset = 10;
  # Sustained and burst package power the chassis can shed.
  pl1 = 55000000;
  pl1Window = 28000000;
  pl2 = 90000000;

  apply = pkgs.writeShellScript "thermal-limits" ''
    for f in /sys/bus/pci/drivers/proc_thermal/*/tcc_offset_degree_celsius; do
      [ -e "$f" ] && echo ${toString tccOffset} > "$f"
    done
    for d in /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl-mmio:0; do
      [ -d "$d" ] || continue
      echo ${toString pl1} > "$d/constraint_0_power_limit_uw"
      echo ${toString pl1Window} > "$d/constraint_0_time_window_us"
      echo ${toString pl2} > "$d/constraint_1_power_limit_uw"
    done
  '';
in
{
  # Reapply on device add, resume.
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="proc_thermal", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart thermal-limits.service"
    ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0|intel-rapl-mmio:0", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart thermal-limits.service"
  '';

  systemd.services.thermal-limits = {
    description = "Apply CPU temperature and power limits";
    wantedBy = [ "multi-user.target" "post-resume.target" ];
    # thermald keeps the RAPL limit it saw at start.
    before = [ "thermald.service" ];
    after = [ "post-resume.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = apply;
    };
  };
}
