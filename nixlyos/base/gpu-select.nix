# Boot-time GPU pick in /run/nixly/gpu.env, and nixly-dgpu to offload onto it.
{ lib, pkgs, ... }:

{
  nixpkgs.overlays = [
    (final: _: {
      # Prints gpu.env; given FILE, replaces it atomically.
      nixly-gpu-select = final.writeShellApplication {
        name = "nixly-gpu-select";
        runtimeInputs = [ final.coreutils ];
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
      };

      # Runs COMMAND fully on the dGPU of a hybrid machine, else plain exec.
      nixly-dgpu = final.writeShellApplication {
        name = "nixly-dgpu";
        text = ''
          node_arg=""
          if [[ ''${1:-} == --node-arg ]]; then
            node_arg=$2
            shift 2
          fi
          (( $# )) || { echo "usage: nixly-dgpu [--node-arg PREFIX] COMMAND [ARGS...]" >&2; exit 2; }

          env=/run/nixly/gpu.env
          [[ -r $env ]] || exec "$@"
          declare -A gpu
          while IFS='=' read -r key value; do gpu[$key]=$value; done < "$env"
          # NVIDIA-rendered sessions need no offload.
          [[ ''${gpu[NIXLY_GPU_HYBRID]:-} == 1 && ''${NIXLY_NVIDIA_PRIMARY:-} != 1 ]] || exec "$@"

          pci=''${gpu[NIXLY_DGPU_PCI]}
          # Live node, since the driver may have reloaded since boot.
          nodes=(/sys/bus/pci/devices/"$pci"/drm/renderD*)
          [[ -e ''${nodes[0]} ]] || exec "$@"
          node=/dev/dri/''${nodes[0]##*/}

          # VA-API driver per kernel driver.
          declare -A va=([nvidia]=nvidia [amdgpu]=radeonsi [radeon]=r600 [nouveau]=nouveau [i915]=iHD [xe]=iHD)
          driver=""
          for d in "''${!va[@]}"; do
            [[ ! -e /sys/bus/pci/drivers/$d/$pci ]] || driver=$d
          done

          export MOZ_DRM_DEVICE=$node GST_VAAPI_DRM_DEVICE=$node
          [[ -z $driver ]] || export LIBVA_DRIVER_NAME=''${va[$driver]}
          if [[ $driver == nvidia ]]; then
            gl=/run/opengl-driver gl32=/run/opengl-driver-32
            icds=$gl/share/vulkan/icd.d/nvidia_icd.json:$gl32/share/vulkan/icd.d/nvidia_icd.json
            export __NV_PRIME_RENDER_OFFLOAD=1 __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0 \
              __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only \
              __EGL_VENDOR_LIBRARY_FILENAMES=$gl/share/glvnd/egl_vendor.d/10_nvidia.json:$gl32/share/glvnd/egl_vendor.d/10_nvidia.json \
              VK_DRIVER_FILES=$icds VK_ICD_FILENAMES=$icds NVD_BACKEND=direct VDPAU_DRIVER=nvidia
          else
            export DRI_PRIME=pci-''${pci//[.:]/_} MESA_VK_DEVICE_SELECT=''${gpu[NIXLY_DGPU_VIDDID]}!
            unset VK_DRIVER_FILES VK_ICD_FILENAMES
          fi
          [[ -z $node_arg ]] || set -- "$1" "$node_arg$node" "''${@:2}"
          exec "$@"
        '';
      };
    })
  ];

  environment.systemPackages = [ pkgs.nixly-dgpu ];

  systemd.services.nixly-gpu-select = {
    description = "Pick the GPU for dGPU offload";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "nixly";
      RuntimeDirectoryPreserve = "yes";
      # Coldplug binds the GPU drivers.
      ExecStartPre = "-${pkgs.systemd}/bin/udevadm settle --timeout=10";
      ExecStart = "${lib.getExe pkgs.nixly-gpu-select} /run/nixly/gpu.env";
    };
  };
}
