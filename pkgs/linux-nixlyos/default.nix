# Kernels from the kernel_nixlyos flake.
{ kernelFlake }:
let
  kernels = kernelFlake.packages.x86_64-linux;
in
{
  generic = kernels.linux-nixlyos;
  v3 = kernels.linux-nixlyos-v3;
  server = kernels.linux-nixlyos-server;
  enterprise = kernels.linux-nixlyos-enterprise;
}
