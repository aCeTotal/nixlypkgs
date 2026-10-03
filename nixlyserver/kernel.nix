# Runtime half; build in pkgs.
{ pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_nixlyserver;

  # Late modules need boot.kernelModules.
  security.lockKernelModules = true;
  security.allowSimultaneousMultithreading = false;
  security.forcePageTableIsolation = true;

  boot.kernelParams = [
    "slab_nomerge"
    "debugfs=off"
    "oops=panic"
    "iommu.passthrough=0"
    "iommu.strict=1"
    "intel_iommu=on"
    "amd_iommu=force_isolation"
    "random.trust_cpu=off"
    "random.trust_bootloader=off"
    "spectre_v2=on"
    "spec_store_bypass_disable=on"
    "tsx=off"
    "l1tf=full,force"
    "gather_data_sampling=force"
  ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.perf_event_paranoid" = 2;
    "dev.tty.ldisc_autoload" = 0;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
    "vm.mmap_rnd_bits" = 32;

    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
  };
}
