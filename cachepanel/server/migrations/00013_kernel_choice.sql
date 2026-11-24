-- +goose Up
-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(source, $old$
  # Kernel builds per CPU level.
  march = { "3" = "_v3"; "4" = "_v4"; };
$old$, $new$
  # Servers share one kernel; AVX2 desktops run v3.
  tuned = if config.nixlyos.mode == "server" then "_server" else lib.optionalString (hw.cpuLevel >= 3) "_v3";
$new$), $old$
        else pkgs."linuxPackages_nixlyos${march.${toString hw.cpuLevel} or ""}";
$old$, $new$
        else pkgs."linuxPackages_nixlyos${tuned}";
$new$),
    revision = revision + 1, updated_at = now()
WHERE slug = 'system' AND strpos(source, '"4" = "_v4";') > 0;
-- +goose StatementEnd

-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(source, $old$
  # Enterprise runs in-tree drivers only.
  enterpriseGpu = {
    assertions = [{
      assertion = config.nixlyos.kernel != "enterprise" || !(builtins.elem "nvidia" config.services.xserver.videoDrivers);
      message = "The enterprise kernel runs in-tree drivers only; NVIDIA's driver needs the performance kernel.";
    }];
  };
$old$, $new$
  # kCFI kernels take in-tree drivers only.
  hardenedGpu = {
    assertions = [{
      assertion = !(config.boot.kernelPackages.kernel.config.isYes "CFI" && builtins.elem "nvidia" config.services.xserver.videoDrivers);
      message = "The enterprise kernel runs in-tree drivers only; NVIDIA's driver needs another kernel.";
    }];
  };
$new$), '++ [ enterpriseGpu ]', '++ [ hardenedGpu ]'),
    revision = revision + 1, updated_at = now()
WHERE slug = 'hardware' AND strpos(source, 'enterpriseGpu = {') > 0;
-- +goose StatementEnd

INSERT INTO module_revisions (module_id, revision, source)
SELECT id, revision, source FROM modules WHERE slug IN ('system', 'hardware')
ON CONFLICT DO NOTHING;

-- +goose Down
SELECT 1;
