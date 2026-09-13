#!/usr/bin/env bash
# Hardware detection for NixlyOS. Nix eval is pure and cannot read /sys, so
# this writes pure data files into ~/.local/nixlyos/hardware (or $1) that
# lib.mkNixlySystem turns into modules. Only data and module *names* are
# written, never paths, so the generated files stay valid across versions.
# Nothing is touched when everything already matches.
set -euo pipefail

OUT=${1:-"$HOME/.local/nixlyos/hardware"}
: "${REGISTER:=}"

write_generated() {
  local path=$1 content=$2
  if [[ -f $path ]] && [[ "$(<"$path")" == "$content" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

# "GS66 Stealth 10UG" -> "gs66-stealth-10ug"
slug() {
  local s=${1,,}
  s=${s//[^a-z0-9]/-}
  while [[ $s == *--* ]]; do s=${s//--/-}; done
  s=${s#-}; s=${s%-}
  printf '%s\n' "$s"
}

# Machine architecture: ARM SBCs (Raspberry Pi etc.) have no DMI and no PCI
# GPU, so they are identified from the device tree further down.
machine=$(uname -m)
is_arm=0
[[ $machine == aarch64 ]] && is_arm=1

# CPU: vendor, cores, feature level.
cpu_name="" cpu_flags="" nproc=0
while IFS= read -r line; do
  case "$line" in
    processor*) (( ++nproc ));;
    vendor_id*GenuineIntel*) [[ -n $cpu_name ]] || cpu_name="intel";;
    vendor_id*AuthenticAMD*) [[ -n $cpu_name ]] || cpu_name="amd";;
    flags*) [[ -n $cpu_flags ]] || cpu_flags=" ${line#*: } ";;
  esac
done < /proc/cpuinfo
(( nproc > 0 )) || nproc=1
# ARM cpuinfo has no vendor_id; the arm cpu module is vendor-neutral.
(( is_arm )) && cpu_name="arm"

# x86-64 psABI level, used to pick conservative settings on old CPUs.
has_flag() { [[ $cpu_flags == *" $1 "* ]]; }
cpu_level=1
if has_flag sse4_2 && has_flag popcnt && has_flag cx16; then cpu_level=2; fi
if (( cpu_level == 2 )) && has_flag avx2 && has_flag bmi2 && has_flag fma; then cpu_level=3; fi
if (( cpu_level == 3 )) && has_flag avx512f && has_flag avx512vl; then cpu_level=4; fi

mem_gib=0
while IFS= read -r line; do
  if [[ $line == MemTotal:* ]]; then
    read -r _ mem_kb _ <<<"$line"
    mem_gib=$(( mem_kb / 1048576 ))
    break
  fi
done < /proc/meminfo
(( mem_gib > 0 )) || mem_gib=1

# GPU
# PCI class 0x03xxxx is a display controller; 10de is NVIDIA, 8086 Intel, 1002 AMD.
has_nvidia=0 has_amd=0 has_intel_igpu=0 has_intel_dgpu=0
has_amd_igpu=0 has_amd_dgpu=0
bus_nvidia="" bus_intel="" bus_amd="" dev_nvidia=""
amd_legacy=0 intel_legacy=0

# Intel DG2 Arc; everything else from 8086 is treated as an iGPU.
dg2_ids=" 5690 5691 5692 5693 5694 5695 5696 5697 56a0 56a1 56a2 56a3 56a5 56a6 "

# The display part of an AMD APU, used only for the status line.
amd_apu_ids=" 1114 13c0 150e 1586 15bf 15c8 15d8 15dd 15e7 1636 1638 163f 164c 164d 164e 1681 98e4 "
amd_is_apu() {
  local d=$1 i=$2
  [[ $amd_apu_ids == *" $d "* ]] ||
  (( i >= 0x1304 && i <= 0x131d )) ||   # Kaveri
  (( i >= 0x9640 && i <= 0x964f )) ||   # Trinity/Richland
  (( i >= 0x9802 && i <= 0x980a )) ||   # Ontario/Zacate
  (( i >= 0x9830 && i <= 0x9856 )) ||   # Kabini/Mullins
  (( i >= 0x9870 && i <= 0x9877 )) ||   # Carrizo/Bristol
  (( i >= 0x9900 && i <= 0x991f ))      # Trinity/Richland (ARUBA)
}

# Old AMD cards that must be forced onto amdgpu or left on radeon. The ranges are
# explicit because AMD's ID space is not monotonic.
amd_is_legacy() {
  local i=$1
  (( i >= 0x1304 && i <= 0x131d )) ||   # Kaveri  (GCN2 APU)
  (( i >= 0x4000 && i <= 0x5fff )) ||   # R300/R400/RV370
  (( i >= 0x6600 && i <= 0x667f )) ||   # Oland/Hainan (GCN1), Bonaire (GCN2)
  (( i >= 0x6720 && i <= 0x677f )) ||   # Northern Islands (TeraScale 3)
  (( i >= 0x6780 && i <= 0x67bf )) ||   # Tahiti (GCN1), Hawaii (GCN2)
  (( i >= 0x6800 && i <= 0x685f )) ||   # Pitcairn/Verde (GCN1), Trinity APU
  (( i >= 0x6880 && i <= 0x68ff )) ||   # Evergreen (TeraScale 2)
  (( i >= 0x7100 && i <= 0x71ff )) ||   # R520/R580
  # Stops before 0x9870: Carrizo and Stoney are GCN3 and belong on plain amdgpu.
  (( i >= 0x9400 && i <= 0x986f ))
}

# Intel Gen7.5 and older need i965, since iHD requires Broadwell or newer.
intel_is_legacy() {
  local i=$1
  (( i <= 0x0f3f )) ||
  (( i >= 0x2500 && i <= 0x2fff )) ||
  (( i >= 0xa000 && i <= 0xa0ff ))
}

# hardware.nvidia.prime.*BusId takes a DECIMAL address while sysfs is hex.
to_bus_id() {
  local a=$1 dom bus slot fn
  dom=${a%%:*}; a=${a#*:}
  bus=${a%%:*}; a=${a#*:}
  slot=${a%%.*}; fn=${a#*.}
  printf 'PCI:%d@%d:%d:%d\n' "$((16#$bus))" "$((16#$dom))" "$((16#$slot))" "$((16#$fn))"
}

for dev in /sys/bus/pci/devices/*; do
  read -r cls < "$dev/class"
  [[ $cls == 0x03* ]] || continue
  read -r vnd < "$dev/vendor"
  read -r did < "$dev/device"
  addr=${dev##*/}
  case "$vnd" in
    0x10de)
      has_nvidia=1
      [[ -n $bus_nvidia ]] || { bus_nvidia=$(to_bus_id "$addr"); dev_nvidia=${did#0x}; }
      ;;
    0x1002)
      has_amd=1
      [[ -n $bus_amd ]] || bus_amd=$(to_bus_id "$addr")
      amd_is_legacy "$((16#${did#0x}))" && amd_legacy=1
      if amd_is_apu "${did#0x}" "$((16#${did#0x}))"; then has_amd_igpu=1; else has_amd_dgpu=1; fi
      ;;
    0x8086)
      if [[ $dg2_ids == *" ${did#0x} "* ]]; then
        has_intel_dgpu=1
      else
        has_intel_igpu=1
        [[ -n $bus_intel ]] || bus_intel=$(to_bus_id "$addr")
        intel_is_legacy "$((16#${did#0x}))" && intel_legacy=1
      fi
      ;;
  esac
done

# NVIDIA architecture to driver branch. The ranges are disjoint and must be
# checked in order, since Fermi and Kepler have interleaved ID blocks. This is a
# heuristic; pin the branch in the laptop register if a card lands wrong.
#   latest  Turing and newer
#   580     Maxwell, Pascal, Volta
#   470     Kepler
#   390     Fermi
#   340     Tesla
nvidia_arch="" nvidia_branch=""
if (( has_nvidia )) && [[ -n $dev_nvidia ]]; then
  id=$((16#$dev_nvidia))
  arch_of() {
    local i=$1
    if   (( i <= 0x06bf )); then echo tesla
    elif (( i <= 0x09ff )); then echo fermi
    elif (( i <= 0x0cff )); then echo tesla
    elif (( i <= 0x0fbf )); then echo fermi
    elif (( i <= 0x103f )); then echo kepler   # GK110
    elif (( i <= 0x117f )); then echo fermi    # GF119, GF108, GF117 (0x1140)
    elif (( i <= 0x11ff )); then echo kepler   # GK104/106/107
    elif (( i <= 0x127f )); then echo fermi    # GF114/GF116
    elif (( i <= 0x133f )); then echo kepler   # GK208 (0x1280+), GK208M
    elif (( i <= 0x1dff )); then echo maxwell_pascal_volta
    else                         echo turing_plus
    fi
  }
  nvidia_arch=$(arch_of "$id")
  case "$nvidia_arch" in
    turing_plus)          nvidia_branch="latest";;
    maxwell_pascal_volta) nvidia_branch="legacy_580";;
    kepler)               nvidia_branch="legacy_470";;
    # legacy_390 and legacy_340 are broken in nixpkgs, and a system that does not
    # build is worse than nouveau.
    fermi|tesla)          nvidia_branch="nouveau";;
  esac
fi

# DMI: laptop or desktop, plus model.
dmi() { [[ -r /sys/class/dmi/id/$1 ]] && read -r _v < "/sys/class/dmi/id/$1" && printf '%s\n' "$_v" || true; }

chassis=$(dmi chassis_type)
sys_vendor=$(dmi sys_vendor)
product=$(dmi product_name)
family=$(dmi product_family)
board=$(dmi board_name)

# SMBIOS chassis types: 8 Portable, 9 Laptop, 10 Notebook, 11 Hand Held,
# 14 Sub Notebook, 30 Tablet, 31 Convertible, 32 Detachable.
is_laptop=0
case "$chassis" in
  8|9|10|11|14|30|31|32) is_laptop=1;;
  # Unknown or misreported chassis: fall back to an actual battery.
  # type=Battery is required, since a UPS or mouse battery reports Device or UPS.
  *) for b in /sys/class/power_supply/*; do
       [[ -r $b/type && -r $b/present ]] || continue
       read -r t < "$b/type"; [[ $t == Battery ]] || continue
       [[ -e $b/scope ]] && { read -r sc < "$b/scope"; [[ $sc == Device ]] && continue; }
       is_laptop=1; break
     done;;
esac

# Vendor slug as nixos-hardware names its modules.
vendor_slug=""
case "${sys_vendor,,}" in
  *micro-star*|*msi*)        vendor_slug=msi;;
  *lenovo*)                  vendor_slug=lenovo;;
  *dell*)                    vendor_slug=dell;;
  *asus*)                    vendor_slug=asus;;
  *hewlett*|hp*|*" hp"*)     vendor_slug=hp;;
  *framework*)               vendor_slug=framework;;
  *acer*)                    vendor_slug=acer;;
  *apple*)                   vendor_slug=apple;;
  *tuxedo*)                  vendor_slug=tuxedo;;
  *system76*)                vendor_slug=system76;;
  *gpd*)                     vendor_slug=gpd;;
  *razer*)                   vendor_slug=razer;;
  *gigabyte*)                vendor_slug=gigabyte;;
  *"star labs"*|*starlabs*)  vendor_slug=starlabs;;
  *slimbook*)                vendor_slug=slimbook;;
  *microsoft*)               vendor_slug=microsoft;;
  *samsung*)                 vendor_slug=samsung;;
  *toshiba*|*dynabook*)      vendor_slug=toshiba;;
  *huawei*)                  vendor_slug=huawei;;
  *panasonic*)               vendor_slug=panasonic;;
  *pcspecialist*|*"pc specialist"*) vendor_slug=pcspecialist;;
  *supermicro*)              vendor_slug=supermicro;;
  *intel*)                   vendor_slug=intel;;
  *)                         vendor_slug=$(slug "$sys_vendor");;
esac

# Model candidates in priority order; the nix side imports the first that exists,
# so a candidate that does not match costs nothing.
candidates=()
[[ -n $vendor_slug && -n $product ]] && candidates+=("$vendor_slug-$(slug "$product")")
[[ -n $vendor_slug && -n $board   ]] && candidates+=("$vendor_slug-$(slug "$board")")
[[ -n $vendor_slug && -n $family  ]] && candidates+=("$vendor_slug-$(slug "$family")")

# ARM SBC: no DMI, so vendor/model come from the device tree. The compatible
# list ("raspberrypi,5-model-bbrcm,bcm2712" NUL-separated) gives both the SoC
# and nixos-hardware candidates: every entry slugged (vendor,board ->
# vendor-board) matches nixos-hardware's naming for most boards, and the
# Raspberry Pi SoC ids map to the raspberry-pi-N modules explicitly. Unknown
# candidates cost nothing (the static loader filters on hasAttr), so a board
# without a nixos-hardware module just falls back to the generic ARM setup.
soc=""
if (( is_arm )); then
  dt_model="" dt_compat=""
  [[ -r /proc/device-tree/model ]] && dt_model=$(tr -d '\0' < /proc/device-tree/model)
  [[ -r /proc/device-tree/compatible ]] && dt_compat=$(tr '\0' ',' < /proc/device-tree/compatible)

  case ",$dt_compat" in
    *,brcm,bcm2712*) soc=rpi5;;
    *,brcm,bcm2711*) soc=rpi4;;
    *,brcm,bcm2837*) soc=rpi3;;
    *,brcm,bcm2836*) soc=rpi2;;
    *)               soc=generic-arm;;
  esac

  candidates=()
  case $soc in
    rpi5) candidates+=("raspberry-pi-5");;
    rpi4) candidates+=("raspberry-pi-4");;
    rpi3) candidates+=("raspberry-pi-3");;
    rpi2) candidates+=("raspberry-pi-2");;
  esac
  IFS=',' read -r -a dt_entries <<< "$dt_compat"
  for e in "${dt_entries[@]}"; do
    [[ -n $e ]] && candidates+=("$(slug "$e")")
  done

  sys_vendor=${dt_compat%%,*}
  vendor_slug=$(slug "$sys_vendor")
  product=$dt_model
fi

# Virtualisation: a guest gets the matching hardware/virt module (guest
# agent, virtio initrd, software-rendering failsafe). systemd-detect-virt is
# always present on NixOS; the DMI fallback covers running from other distros.
virt=none
if command -v systemd-detect-virt >/dev/null 2>&1; then
  v=$(systemd-detect-virt --vm 2>/dev/null || true)
else
  case "$sys_vendor $product" in
    QEMU*)              v=qemu;;
    *VMware*)           v=vmware;;
    "innotek GmbH"*)    v=oracle;;
    *Microsoft*Virtual*) v=microsoft;;
    *Parallels*)        v=parallels;;
    *)                  v=none;;
  esac
fi
case "$v" in
  qemu|kvm|bochs|amazon) virt=kvm;;
  vmware)                virt=vmware;;
  oracle)                virt=virtualbox;;
  microsoft)             virt=hyperv;;
  parallels)             virt=parallels;;
  none|"")               virt=none;;
  *)                     virt=kvm;;   # unknown hypervisor: virtio + llvmpipe is the safe guess
esac

# Bootloader mode: EFI machines keep systemd-boot; an SBC booted via
# U-Boot/RPi firmware needs extlinux; a legacy-BIOS machine (typically a VM
# with default firmware) needs grub on the disk that holds the root FS.
boot_mode=efi boot_device=""
if [[ ! -d /sys/firmware/efi ]]; then
  if (( is_arm )); then
    boot_mode=extlinux
  else
    boot_mode=bios
    if command -v findmnt >/dev/null 2>&1 && command -v lsblk >/dev/null 2>&1; then
      rootsrc=$(findmnt -no SOURCE / 2>/dev/null || true)
      pk=$(lsblk -no PKNAME "${rootsrc%%\[*}" 2>/dev/null | head -n1 || true)
      [[ -n $pk ]] && boot_device="/dev/$pk"
    fi
  fi
fi

# Register of explicit overrides, first match wins.
# Line format: vendor-glob, product-glob, comma-separated modules, nvidia branch.
reg_modules="" reg_branch=""
if [[ -n $REGISTER && -f $REGISTER ]]; then
  while IFS='|' read -r r_vendor r_product r_mods r_branch; do
    [[ -z ${r_vendor// } || ${r_vendor// } == \#* ]] && continue
    r_vendor=${r_vendor// }
    # Trim without forking; the register is read on every eval.
    r_product=${r_product#"${r_product%%[![:space:]]*}"}
    r_product=${r_product%"${r_product##*[![:space:]]}"}
    # shellcheck disable=SC2053  # register entries are globs by design
    [[ ${vendor_slug,,} == ${r_vendor,,} || $r_vendor == '*' ]] || continue
    # shellcheck disable=SC2053
    [[ ${product,,} == ${r_product,,} || $r_product == '*' ]] || continue
    reg_modules=${r_mods// }
    reg_branch=${r_branch// }
    break
  done < "$REGISTER"
fi
[[ -n $reg_branch ]] && nvidia_branch=$reg_branch

# Generic set: laptop versus desktop, SSD versus HDD.
rotational=1
for b in /sys/block/*; do
  [[ -r $b/removable && -r $b/queue/rotational ]] || continue
  read -r rm < "$b/removable"; [[ $rm == 0 ]] || continue
  read -r rot < "$b/queue/rotational"
  [[ $rot == 0 ]] && { rotational=0; break; }
done

generic=()
if (( is_laptop )); then
  generic+=("common-pc-laptop")
  (( rotational )) && generic+=("common-pc-laptop-hdd") || generic+=("common-pc-laptop-ssd")
else
  generic+=("common-pc")
  (( rotational )) && generic+=("common-pc-hdd") || generic+=("common-pc-ssd")
fi

# The register can add modules, and the "no-model" pseudo-module disables the
# DMI-derived one, because a nixos-hardware model module can set options that do
# not exist in the stable nixpkgs this flake uses, breaking the whole eval.
if [[ -n $reg_modules ]]; then
  IFS=',' read -r -a extra <<< "$reg_modules"
  for m in "${extra[@]}"; do
    if [[ $m == no-model ]]; then
      candidates=()
    else
      generic+=("$m")
    fi
  done
fi

# GPU module selection, by name; mkNixlySystem maps names to modules.
gpu_mods=()
if (( has_nvidia )); then
  if [[ $nvidia_branch == nouveau ]]; then
    gpu_mods+=("nvidia_nouveau")
  elif [[ -n $nvidia_branch && $nvidia_branch != latest ]]; then
    # Old card: a profile module that pins the legacy branch and only enables
    # prime when an iGPU is actually present.
    gpu_mods+=("nvidia_legacy")
  elif (( has_intel_igpu )); then
    # Hybrid: prime offload against the iGPU-driven panel.
    gpu_mods+=("nvidia_intel")
  else
    gpu_mods+=("nvidia_only")
  fi
fi
(( has_intel_dgpu )) && gpu_mods+=("intel")
# The iGPU module owns i915 firmware and VA-API decoding for the compositor, so
# it is included even when NVIDIA drives the session.
if (( has_intel_igpu )); then
  (( intel_legacy )) && gpu_mods+=("intel_legacy") || gpu_mods+=("intel_igpu")
fi
# The AMD module is shared by iGPU and dGPU, but dropped when NVIDIA drives the
# session, since its radeonsi session variables would point at the wrong driver.
if (( has_amd && !has_nvidia )); then
  (( amd_legacy )) && gpu_mods+=("amd_legacy") || gpu_mods+=("amd")
fi

# Devices that gate services.
# The Bluetooth controller appears under /sys/class/bluetooth once btusb loads;
# the USB fallback covers a live ISO where the module is not loaded yet.
has_bt=0
for b in /sys/class/bluetooth/*; do [[ -e $b ]] && { has_bt=1; break; }; done
if (( !has_bt )); then
  for u in /sys/bus/usb/devices/*/bDeviceClass; do
    [[ -r $u ]] || continue
    read -r c < "$u"; [[ $c == e0 ]] && { has_bt=1; break; }
  done
fi

# Known USB vendors for fprintd-supported fingerprint readers.
fp_vendors=" 27c6 138a 06cb 1c7a 08ff 04f3 05ba 298d 1491 "
has_fp=0
for u in /sys/bus/usb/devices/*/idVendor; do
  [[ -r $u ]] || continue
  read -r v < "$u"
  [[ $fp_vendors == *" $v "* ]] && { has_fp=1; break; }
done

# A Thunderbolt domain appears once the controller is present; boltd handles
# device authorisation.
has_tb=0
for t in /sys/bus/thunderbolt/devices/domain*; do [[ -e $t ]] && { has_tb=1; break; }; done

# devices.nix: module gating services on hardware that is actually present.
# WiFi is deliberately not gated: wpa_supplicant is a no-op without a card
# and nixlytile hides the wifi UI when no adapter exists.
write_generated "$OUT/devices.nix" \
"{ lib, ... }:

{$( ((has_bt)) || printf '%s' "
  hardware.bluetooth.enable = lib.mkForce false;
")$( ((has_fp)) && printf '%s' "
  services.fprintd.enable = true;
")$( ((has_tb)) && printf '%s' "
  services.hardware.bolt.enable = true;
")
}"

# dmi.nix: pure data, read by modules that need to know which machine they run on.
write_generated "$OUT/dmi.nix" \
"{
  vendor = \"$sys_vendor\";
  vendorSlug = \"$vendor_slug\";
  product = \"$product\";
  board = \"$board\";
  chassis = \"$chassis\";
  isLaptop = $( ((is_laptop)) && echo true || echo false );
}"

# resources.nix.
# max-jobs times cores must fit in RAM, not just in the core count: one job per
# 8 GiB, never more than a quarter of the cores, and cores per job capped by both.
jobs=$(( mem_gib / 8 ))
(( jobs > nproc / 4 )) && jobs=$(( nproc / 4 ))
(( jobs < 1 )) && jobs=1
build_cores=$(( nproc / jobs / 4 ))
mem_cores=$(( mem_gib / 4 ))
(( build_cores > mem_cores )) && build_cores=$mem_cores
(( build_cores < 2 )) && build_cores=2

write_generated "$OUT/resources.nix" \
"{
  cores = $nproc;
  memGiB = $mem_gib;
  cpuLevel = $cpu_level;
  maxJobs = $jobs;
  buildCores = $build_cores;
}"

# detected.nix.
write_generated "$OUT/detected.nix" \
"{
  nvidia = \"$bus_nvidia\";
  intel = \"$bus_intel\";
  amd = \"$bus_amd\";
  nvidiaArch = \"$nvidia_arch\";
  nvidiaBranch = \"${nvidia_branch:-latest}\";
}"

# platform.nix: architecture, SBC SoC, boot path and hypervisor. mk-system
# derives the nix system from arch and picks the virt guest module; boot.nix
# picks systemd-boot versus extlinux from bootMode.
write_generated "$OUT/platform.nix" \
"{
  arch = \"$( ((is_arm)) && echo aarch64 || echo x86_64 )\";
  soc = $( [[ -n $soc ]] && printf '"%s"' "$soc" || echo null );
  bootMode = \"$boot_mode\";
  bootDevice = $( [[ -n $boot_device ]] && printf '"%s"' "$boot_device" || echo null );
  virt = \"$virt\";
}"

# profile.nix: nixos-hardware module names and flags, mapped to modules by
# the static loader in the nixlyos tree.
cand_nix="" gen_nix=""
for c in "${candidates[@]}"; do cand_nix+="    \"$c\"
"; done
for g in "${generic[@]}"; do gen_nix+="    \"$g\"
"; done

# msi-ec must not load on non-MSI hardware.
msi_ec=false
(( is_laptop )) && [[ $vendor_slug == msi ]] && msi_ec=true

write_generated "$OUT/profile.nix" \
"{
  candidates = [
$cand_nix  ];

  generic = [
$gen_nix  ];

  msiEc = $msi_ec;
  isLaptop = $( ((is_laptop)) && echo true || echo false );
}"

# selection.nix: cpu vendor and GPU stack, by module name.
gpus_nix=""
for g in "${gpu_mods[@]}"; do gpus_nix+=" \"$g\""; done
write_generated "$OUT/selection.nix" \
"{
  cpu = $( [[ -n $cpu_name ]] && printf '"%s"' "$cpu_name" || echo null );
  gpus = [$gpus_nix ];
}"

# Status line.
case $cpu_name in
  intel) cpu_pretty="Intel";;
  amd)   cpu_pretty="AMD";;
  arm)   cpu_pretty="ARM";;
  *)     cpu_pretty="Unknown";;
esac
gpu_names=()
(( has_intel_igpu )) && gpu_names+=("Intel iGPU")
(( has_amd_igpu )) && gpu_names+=("AMD iGPU")
(( has_nvidia )) && gpu_names+=("Nvidia dedicated GPU")
(( has_amd_dgpu )) && gpu_names+=("AMD dedicated GPU")
(( has_intel_dgpu )) && gpu_names+=("Intel dedicated GPU")

line="$cpu_pretty CPU"
for i in "${!gpu_names[@]}"; do
  (( i == 0 )) && line+=" + ${gpu_names[i]}" || line+=" | ${gpu_names[i]}"
done
[[ -n $soc ]] && line+=" ($soc)"
[[ $virt != none ]] && line+=" [VM: $virt]"
echo "ok: $line detected -> $OUT"
