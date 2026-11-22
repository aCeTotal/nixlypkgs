{ writeShellApplication }:

# Runs a command on the dGPU.
writeShellApplication {
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
}
