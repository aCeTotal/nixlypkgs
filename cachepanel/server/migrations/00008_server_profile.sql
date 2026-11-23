-- +goose Up
-- Laptops follow the desktop profile.
DELETE FROM profiles WHERE name = 'laptop';

UPDATE modules SET required = false WHERE slug IN ('session', 'audio');

INSERT INTO profile_modules (profile_id, module_id)
SELECT p.id, m.id FROM profiles p JOIN modules m ON m.slug IN ('session', 'audio')
WHERE p.platform IN ('desktop', 'htpc')
ON CONFLICT DO NOTHING;

-- +goose StatementBegin
UPDATE modules SET
    source = replace(replace(source,
        'type = lib.types.enum [ "desktop" "htpc" ];',
        'type = lib.types.enum [ "desktop" "htpc" "server" ];'),
        E'  # Battery policy, never the HTPC.\n  laptop = hwData.dmi.isLaptop && !isHtpc;',
        E'  # Battery policy, desktops only.\n  laptop = hwData.dmi.isLaptop && config.nixlyos.mode == "desktop";'),
    revision = revision + 1, updated_at = now()
WHERE slug = 'system' AND source LIKE '%lib.types.enum [ "desktop" "htpc" ];%';
-- +goose StatementEnd

UPDATE modules SET position = 12 WHERE slug = 'hardware';

-- +goose StatementBegin
INSERT INTO modules (slug, title, description, required, position, source) VALUES
('server', 'Server', 'Headless machines: no desktop, audio or games, and they never sleep.', false, 11, $nix${ config, lib, ... }:

let
  # Servers never sleep.
  awake = {
    systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: { enable = false; });
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };
  };
in
{
  imports = [ awake ];

  assertions = [{
    assertion = config.nixlyos.mode == "server";
    message = "The server module belongs to profiles on the server platform.";
  }];
}
$nix$);
-- +goose StatementEnd

INSERT INTO module_revisions (module_id, revision, source)
SELECT id, revision, source FROM modules WHERE slug IN ('system', 'server')
ON CONFLICT DO NOTHING;

UPDATE modules m SET title = t.title, description = t.description
FROM (VALUES
    ('system', 'System', 'Boot, kernel, Nix, users, locale, performance, memory, power and update tools.'),
    ('security', 'Security', 'Firewall, sandboxing, reduced attack surface, Secure Boot and snapshots.'),
    ('network', 'Network', 'TCP and DNS, Wi-Fi, queueing, VPN, SSH and NFS.'),
    ('session', 'Session', 'Wayland, nixlytile, login, mouse and keyboard.'),
    ('audio', 'Audio and Bluetooth', 'PipeWire, microphone chain, push-to-talk and Bluetooth.'),
    ('user', 'User environment', 'Shell, terminal, git, theme and editor.'),
    ('gaming', 'Gaming', 'Steam, Proton, GeForce NOW, controllers, game mode and emulators.'),
    ('apps', 'Applications', 'Browser, media, office, RSS and text browser.'),
    ('desktop', 'Desktop', 'Workstations and laptops: Citrix, Claude Code, Blender, FreeCAD, Gaea, Unreal, RetroArch, calculator and PDF.'),
    ('htpc', 'HTPC', 'Living-room mode: one app at a time, media, TV audio and nightly updates.'),
    ('hardware', 'Hardware', 'CPU, graphics, mainboard, virtualisation and peripherals, chosen by the hardware.'))
    AS t(slug, title, description)
WHERE m.slug = t.slug;

UPDATE profiles p SET description = t.description
FROM (VALUES
    ('desktop', 'Workstations and laptops'),
    ('htpc', 'Living-room box with Steam, GeForce NOW and media')) AS t(name, description)
WHERE p.name = t.name;

INSERT INTO profiles (name, title, platform, description)
VALUES ('server', 'Server', 'server', 'Headless machines on the NixlyOS base')
ON CONFLICT (name) DO NOTHING;

INSERT INTO profile_modules (profile_id, module_id)
SELECT p.id, m.id FROM profiles p JOIN modules m ON m.slug = 'server'
WHERE p.name = 'server'
ON CONFLICT DO NOTHING;

-- +goose Down
DELETE FROM profiles WHERE name = 'server';
DELETE FROM modules WHERE slug = 'server';
UPDATE modules SET position = 11 WHERE slug = 'hardware';
DELETE FROM profile_modules pm USING modules m WHERE pm.module_id = m.id AND m.slug IN ('session', 'audio');
UPDATE modules SET required = true WHERE slug IN ('session', 'audio');
