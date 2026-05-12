{ config, lib, pkgs, ... }:

let
  cfg = config.programs.nixly_steam;
in
{
  options.programs.nixly_steam = {
    enable = lib.mkEnableOption
      "nixly_steam — Steam wrapper with GPU-vendor-specific gaming defaults";

    gpu = lib.mkOption {
      type = lib.types.enum [ "auto" "amd" "nvidia" "intel" ];
      default = "auto";
      example = "amd";
      description = ''
        GPU vendor for which to bake universally-safe env defaults into
        the launcher.

        - `auto` — detect at Steam launch via `/sys/class/drm/cardN/device/vendor`
          and `/proc/driver/nvidia/version`. NVIDIA wins if present; otherwise
          AMD beats Intel. Sets the matching vendor block at runtime.
        - `amd` / `nvidia` / `intel` — bake that vendor's block directly,
          skipping detection. Cleaner env at runtime; mismatch with actual
          hardware silently ignored by the drivers.

        Vendor blocks contain only env vars that apply universally to games
        on that vendor (no per-game tweaks, no controversial flags). The
        generic block (`VKD3D_CONFIG=dxr,dxr11`, `WINE_FULLSCREEN_FSR=1`,
        `PROTON_USE_NTSYNC=1`) is always applied on top. See
        `pkgs/nixly_steam/gpu-params.nix` for the exact lists.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        Resolved `nixly_steam` package with the selected `gpuVendor`
        baked in. Reference this from your own
        `environment.systemPackages` if you also reference nixly_steam
        elsewhere, to avoid two copies (different store paths) colliding
        on `$out/bin/nixly_steam`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nixly_steam.package = pkgs.nixly_steam.override {
      gpuVendor = cfg.gpu;
    };

    environment.systemPackages = [ cfg.package ];
  };
}
