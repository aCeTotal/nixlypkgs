{ lib, config, ... }:

lib.mkIf (config.nixlyos.mode == "htpc") {
  # Small queues: cheap softirq prunes.
  boot.kernel.sysctl = {
    "net.core.rmem_max" = lib.mkForce 8388608;
    "net.ipv4.tcp_rmem" = lib.mkForce "4096 262144 8388608";
  };
}
