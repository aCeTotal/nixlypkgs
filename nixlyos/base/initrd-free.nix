{ pkgs, ... }:

# Kernel 7 leaves initramfs in RAM.
let
  pin = "/run/nixly-initrd";
in
{
  boot.initrd.systemd.services.nixly-initrd-pin = {
    description = "Carry the initramfs across switch-root";
    unitConfig.DefaultDependencies = false;
    after = [ "initrd-switch-root.target" ];
    before = [ "initrd-switch-root.service" ];
    wantedBy = [ "initrd-switch-root.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [ "/bin/mkdir -p ${pin}" "/bin/mount --bind / ${pin}" ];
    };
  };

  systemd.services.nixly-initrd-free = {
    description = "Free the initramfs";
    wantedBy = [ "sysinit.target" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathIsMountPoint = pin;
    };
    path = [ pkgs.util-linux ];
    serviceConfig.Type = "oneshot";
    script = ''
      case $(stat -f -c %T ${pin}) in ramfs|tmpfs) ;; *) exit 1 ;; esac
      find ${pin} -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
      umount ${pin}
      rmdir ${pin}
    '';
  };
}
