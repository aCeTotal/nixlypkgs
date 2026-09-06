{ config, lib, pkgs, hwData, ... }:

let
  hw = hwData.resources;
in
{
  zramSwap = {
    enable = true;
    memoryPercent = 100;          # Use up to 100% of RAM as compressed swap
    # zstd compresses best but costs CPU per page; weak CPUs get lz4 instead,
    # which pages faster at a worse ratio. Chosen by scripts/detect-hw.sh.
    algorithm = if hw.cpuLevel >= 3 && hw.cores >= 8 then "zstd" else "lz4";
    priority = 100;               # Higher priority than disk swap
  };

  boot.kernel.sysctl = {
    # Swap behavior tuned for zram
    "vm.swappiness" = 180;        # Higher for zram (kernel 5.8+)
    "vm.page-cluster" = 0;        # Disable readahead for zram (random access is fast)
    "vm.vfs_cache_pressure" = 50; # Keep dentries/inodes in cache longer

    # Byte-based dirty thresholds behave consistently regardless of RAM use;
    # ratio mode shifts under pressure and can stall game writes.
    "vm.dirty_background_bytes" = 67108864;   # 64 MiB
    "vm.dirty_bytes" = 268435456;             # 256 MiB
    "vm.dirty_expire_centisecs" = 3000;
    "vm.dirty_writeback_centisecs" = 1500;

    # Memory overcommit for gaming
    "vm.overcommit_memory" = 1;   # Always allow overcommit (games often over-allocate)
    "vm.min_free_kbytes" = 131072; # Keep 128MB free minimum
  };

  # systemd-oomd off: earlyoom already covers this, and two killers could each
  # take a different process for the same pressure event.
  systemd.oomd.enable = false;
}
