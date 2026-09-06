{ config, pkgs, lib, ... }:

let
  cfg = config.nixly.blender;

  # The official LTS binary ships every Cycles kernel precompiled, so `variant`
  # only picks which backend the bootstrap enables.
  blenderPkg = pkgs.Blender_bin_lts;

  blenderBin = lib.getExe blenderPkg;

  # OPTIX for RTX, CUDA for older NVIDIA, HIP for AMD, ONEAPI for Intel Arc.
  cyclesDevice = {
    nvidia = "OPTIX";
    amd    = "HIP";
    intel  = "ONEAPI";
  }.${cfg.variant};

  acceptedDeviceTypes = {
    nvidia = [ "OPTIX" "CUDA" ];
    amd    = [ "HIP" ];
    intel  = [ "ONEAPI" ];
  }.${cfg.variant};

  # Bundled with Blender under legacy module IDs.
  bundledAddons = [ "node_wrangler" "rigify" ];

  # extensions.blender.org pkg_ids; the "extra_curve_objectes" typo is upstream's.
  extensionAddons = [
    "looptools"
    "f2"
    "auto_mirror"
    "copy_attributes_menu"
    "bool_tool"
    "extra_mesh_objects"
    "extra_curve_objectes"
  ];

  # Pinned zips whose URLs are content-addressed, so bump URL and hash together.
  fetchExt = url: sha256: pkgs.fetchurl { inherit url sha256; };
  extZips = {
    looptools = fetchExt
      "https://extensions.blender.org/download/sha256:ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108/add-on-looptools-v4.7.7.zip"
      "ff1ca3b3fff73094379da8b1fa2c1acbc9d88d26b7dfc73bb9de5941a6b50108";
    f2 = fetchExt
      "https://extensions.blender.org/download/sha256:dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c/add-on-f2-v1.8.5.zip"
      "dc8f19637a61c332b3eb937a6b86e2363511cbb29a9a22ea8571fe7d924ab05c";
    auto_mirror = fetchExt
      "https://extensions.blender.org/download/sha256:68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7/add-on-auto-mirror-v2.5.4.zip"
      "68c7785f641c91905b07b8122af6a0147834e9a7b77285966253b1f770f30cc7";
    copy_attributes_menu = fetchExt
      "https://extensions.blender.org/download/sha256:990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478/add-on-copy-attributes-menu-v0.6.3.zip"
      "990bac36be4c6a39c4506c84a689c5ec45e1a4b43995542cd0b058663f190478";
    bool_tool = fetchExt
      "https://extensions.blender.org/download/sha256:9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d/add-on-bool-tool-v2.0.0.zip"
      "9d9c73f2f49af05e3a3cfe78daa43676b1005fcbb591dc054d9d04c370f0d85d";
    extra_mesh_objects = fetchExt
      "https://extensions.blender.org/download/sha256:c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b/add-on-extra-mesh-objects-v0.4.1.zip"
      "c85ce4bb2820d5af26b4dad66bf1a0fdeb4bfeffc668c5e4f098f1e416ed434b";
    extra_curve_objectes = fetchExt
      "https://extensions.blender.org/download/sha256:4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909/add-on-extra-curve-objectes-v0.2.0.zip"
      "4ca91ce5563d094694b2c7f1fc9acece8b5ba8f5dd017a49f080e9cfa5553909";
  };
  extZipPaths = lib.mapAttrsToList (_: zip: "${zip}") extZips;

  # BlenderKit lives on GitHub, so its source dir is symlinked into legacy addons/.
  blenderkitSrc = pkgs.fetchFromGitHub {
    owner = "BlenderKit";
    repo  = "BlenderKit";
    rev   = "5d252bee50bef7e409caad047432c028c28e10fa";
    hash  = "sha256-QIwMDN4B3XDoi+OMnuURpRv/1bs7bzfBRbsdRBFNe3Y=";
  };

  setupPy = pkgs.writeText "blender-setup.py" ''
    import bpy, addon_utils

    bundled         = ${builtins.toJSON bundledAddons}
    extension_ids   = ${builtins.toJSON extensionAddons}
    extension_zips  = ${builtins.toJSON extZipPaths}
    accepted_devs   = ${builtins.toJSON acceptedDeviceTypes}
    cycles_dev_type = "${cyclesDevice}"

    def safe(label, fn):
        try: fn()
        except Exception as e: print(f"[setup] {label}: {e}")

    # Install pinned extensions from local zips.
    for z in extension_zips:
        safe(f"install {z}", lambda z=z: bpy.ops.extensions.package_install_files(
            filepath=z, repo="user_default", enable_on_install=True))

    # Enable bundled addons and BlenderKit.
    for a in bundled + ["blenderkit"]:
        safe(f"enable {a}", lambda a=a:
            addon_utils.enable(a, default_set=True, persistent=True))

    # Re-enable extensions in case enable_on_install missed any.
    for ext in extension_ids:
        mod = f"bl_ext.user_default.{ext}"
        safe(f"enable ext {ext}", lambda mod=mod:
            bpy.ops.preferences.addon_enable(module=mod))

    # Cycles compute device.
    def setup_cycles():
        cprefs = bpy.context.preferences.addons["cycles"].preferences
        cprefs.compute_device_type = cycles_dev_type
        cprefs.refresh_devices()
        for d in cprefs.devices:
            d.use = d.type in accepted_devs
    safe("cycles devices", setup_cycles)

    # System and performance
    sysprefs = bpy.context.preferences.system
    safe("gpu_backend",       lambda: setattr(sysprefs, "gpu_backend", "VULKAN"))
    safe("memory_cache",      lambda: setattr(sysprefs, "memory_cache_limit", 8192))
    safe("gpu_subdivision",   lambda: setattr(sysprefs, "use_gpu_subdivision", True))

    # Edit and undo
    edit = bpy.context.preferences.edit
    edit.undo_steps = 256
    edit.undo_memory_limit = 1024

    # Input
    inp = bpy.context.preferences.inputs
    inp.view_rotate_method            = "TURNTABLE"
    inp.use_zoom_to_mouse             = True
    inp.use_rotate_around_active      = True   # Orbit Around Selection
    inp.use_auto_depth                = True   # Auto Depth (under Orbit Around Selection)
    inp.use_mouse_emulate_3_button    = True
    inp.mouse_emulate_3_button_modifier = "ALT"
    safe("tablet_api", lambda: setattr(inp, "tablet_api", "AUTOMATIC"))

    # View and UI
    bpy.context.preferences.view.ui_scale = 1.5

    # Save
    bpy.ops.wm.save_userpref()
    print("[setup] complete")
  '';
in
{
  options.nixly.blender = {
    variant = lib.mkOption {
      type = lib.types.enum [ "nvidia" "amd" "intel" ];
      default = "nvidia";
      description = "Blender GPU variant — picks Cycles backend + auto-enabled compute device";
    };
  };

  config = {
    # Only blender on the system, no source-built variants.
    home.packages = [ blenderPkg ];

    # BlenderKit is a free GPL addon, not on extensions.blender.org.
    home.file.".config/blender/5.2/scripts/addons/blenderkit".source = blenderkitSrc;

    # One-time bootstrap, idempotent via a flag file; delete it and re-switch to rerun.
    home.activation.blenderSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      FLAG="$HOME/.config/blender/.nix_setup_v2"
      if [ ! -f "$FLAG" ] && [ -x "${blenderBin}" ]; then
        echo "[blender] bootstrapping addons + prefs (one-time)..."
        mkdir -p "$HOME/.config/blender"
        if "${blenderBin}" --background --python "${setupPy}"; then
          touch "$FLAG"
          echo "[blender] setup complete"
        else
          echo "[blender] setup failed; will retry on next HM rebuild"
        fi
      fi
    '';
  };
}
