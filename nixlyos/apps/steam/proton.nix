# Latest prebuilt Proton-CachyOS via chaotic-nyx (a plain fetch of the official
# CachyOS release tarball, never built from source). x86-64-v3 build when the
# CPU supports it, generic x86_64 otherwise.
{ inputs, system, hwData }:
let
  chaotic = inputs.chaotic.unrestrictedPackages.${system};
in
if hwData.resources.cpuLevel >= 3
then chaotic.proton-cachyos_x86_64_v3
else chaotic.proton-cachyos
