# NixlyOS gaming-kernel, bygget av kernel_nixlyos-flaken (nixlyos-kernel-input).
# Siste stabile kernel + CachyOS-saus: BORE, sched_ext (scx_lavd), 1000Hz,
# full tickless/preempt, -O3, thin-LTO, BBR3. To varianter:
#   generic — alle x86-64-CPUer
#   v3      — x86-64-v3 (AVX2-generasjonen)
{ kernelFlake }:
{
  generic = kernelFlake.packages.x86_64-linux.linux-nixlyos;
  v3 = kernelFlake.packages.x86_64-linux.linux-nixlyos-v3;
}
