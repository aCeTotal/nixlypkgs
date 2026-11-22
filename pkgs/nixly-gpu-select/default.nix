{ writeShellApplication, coreutils }:

# Boot-time GPU pick.
writeShellApplication {
  name = "nixly-gpu-select";
  runtimeInputs = [ coreutils ];
  text = ''
    declare -A vendors=([0x10de]=nvidia [0x1002]=amd [0x8086]=intel)

    # Intel at 00:02.0; AMD APUs on bus 00 or behind GPP bridge 00:08.1.
    integrated() {
      case $1 in
        intel) [[ ''${2##*/} == 0000:00:02.0 ]] ;;
        amd) [[ ''${2##*/} == ????:00:* || $(readlink -f "$2") == */0000:00:08.1/* ]] ;;
        *) return 1 ;;
      esac
    }

    # Driver-reported VRAM, else the largest memory BAR.
    vram() {
      local f start end flags bar size=0
      for f in "$1/mem_info_vram_total" "$1/tile0/physical_vram_size_bytes"; do
        [[ -r $f ]] || continue
        read -r size < "$f"
        echo "$size"
        return
      done
      while read -r start end flags; do
        bar=$(( flags & 0x200 ? end - start + 1 : 0 ))
        size=$(( bar > size ? bar : size ))
      done < "$1/resource"
      echo "$size"
    }

    count=0 best=-1 hybrid=0 dgpu="" igpu=""
    for dev in /sys/bus/pci/devices/*; do
      read -r class < "$dev/class"
      read -r vid < "$dev/vendor"
      read -r did < "$dev/device"
      vendor=''${vendors[$vid]:-}
      [[ $class == 0x03* && -n $vendor ]] || continue
      count=$(( count + 1 ))
      if integrated "$vendor" "$dev"; then
        [[ -n $igpu ]] || igpu=$dev igpu_vendor=$vendor
        continue
      fi
      rank=$(vram "$dev")
      # NVIDIA outranks any VRAM size.
      [[ $vendor != nvidia ]] || rank=$(( rank + (1 << 50) ))
      (( rank > best )) || continue
      best=$rank dgpu=$dev dgpu_vendor=$vendor dgpu_viddid=''${vid#0x}:''${did#0x}
    done
    [[ -z $dgpu ]] || hybrid=$(( count > 1 ))

    emit() {
      echo "NIXLY_GPU_HYBRID=$hybrid"
      if [[ -n $dgpu ]]; then
        local nodes=("$dgpu"/drm/renderD*)
        printf '%s\n' "NIXLY_DGPU_PCI=''${dgpu##*/}" "NIXLY_DGPU_VENDOR=$dgpu_vendor" \
          "NIXLY_DGPU_VIDDID=$dgpu_viddid"
        [[ ! -e ''${nodes[0]} ]] || echo "NIXLY_DGPU_RENDER=/dev/dri/''${nodes[0]##*/}"
      fi
      [[ -z $igpu ]] || printf '%s\n' "NIXLY_IGPU_PCI=''${igpu##*/}" "NIXLY_IGPU_VENDOR=$igpu_vendor"
    }

    (( $# )) || { emit; exit 0; }
    umask 022
    emit > "$1.tmp"
    mv -f "$1.tmp" "$1"
  '';
}
