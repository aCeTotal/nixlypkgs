# Stabilpatcher oppå CachyOS-taggen.
{
  patches = [
    {
      url = "https://cdn.kernel.org/pub/linux/kernel/v7.x/incr/patch-7.3.5-6.xz";
      hash = "sha256-+XOEZPSHvbseGbGhq0H4Bx1LDO7VH+iGYxw9XkAjTeU=";
    }
  ];
  # Slås sammen i stable-fixup.patch.
  conflicts = [ "drivers/block/zram/zram_drv.c" "drivers/bluetooth/btusb.c" "drivers/gpu/drm/tiny/appletbdrm.c" "include/linux/kernel_stat.h" "kernel/sched/cputime.c" "kernel/sched/fair.c" "kernel/time/tick-sched.c" "security/apparmor/match.c" ];
}
