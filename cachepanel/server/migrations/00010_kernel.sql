-- +goose Up
CREATE TYPE kernel AS ENUM ('performance', 'enterprise');

ALTER TABLE profiles ADD COLUMN kernel kernel NOT NULL DEFAULT 'performance';

-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(replace(replace(replace(source,
        $old$
      description = "NixlyOS machine role; the profile sets it.";
    };
$old$, $new$
      description = "NixlyOS machine role; the profile sets it.";
    };

    options.nixlyos.kernel = lib.mkOption {
      type = lib.types.enum [ "performance" "enterprise" ];
      default = "performance";
      description = "NixlyOS kernel; the profile sets it.";
    };
$new$),
        $old$
  hw = hwData.resources;
$old$, $new$
  hw = hwData.resources;
  # Kernel builds per CPU level.
  march = { "3" = "_v3"; "4" = "_v4"; };
$new$),
        $old$
        else if hw.cpuLevel >= 3
        then pkgs.linuxPackages_nixlyos_v3
        else pkgs.linuxPackages_nixlyos;
$old$, $new$
        else if config.nixlyos.kernel == "enterprise"
        then pkgs.linuxPackages_nixlyos_enterprise
        else pkgs."linuxPackages_nixlyos${march.${toString hw.cpuLevel} or ""}";
$new$),
        $old$
in
{
  imports = [
    mode
$old$, $new$

  # Enterprise freezes modules after boot.
  moduleLock = lib.mkIf (config.nixlyos.kernel == "enterprise") {
    systemd.services.nixly-module-lock = {
      description = "Lock kernel module loading";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" "systemd-udev-trigger.service" "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${config.systemd.package}/bin/udevadm settle";
        ExecStart = "${pkgs.procps}/bin/sysctl -w kernel.modules_disabled=1";
      };
    };
  };
in
{
  imports = [
    mode
$new$),
        $old$
    hibernate
    tools
  ];
$old$, $new$
    hibernate
    tools
    moduleLock
  ];
$new$),
    revision = revision + 1, updated_at = now()
WHERE slug = 'system'
    AND strpos(source, 'then pkgs.linuxPackages_nixlyos_v3') > 0
    AND strpos(source, E'    hibernate\n    tools\n  ];') > 0;
-- +goose StatementEnd

INSERT INTO module_revisions (module_id, revision, source)
SELECT id, revision, source FROM modules WHERE slug = 'system'
ON CONFLICT DO NOTHING;

-- +goose Down
ALTER TABLE profiles DROP COLUMN kernel;
DROP TYPE kernel;
