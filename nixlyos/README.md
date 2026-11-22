# NixlyOS

The whole NixlyOS system, built from this repo via `lib.mkNixlySystem`.
Machines carry no configuration tree — only `~/.local/nixlyos`:

```
~/.local/nixlyos/
  flake.nix     tiny; nixlypkgs revision and profile tree pinned by the panel
  flake.lock    the machine's pin — updates only via nixlyos-update
  profile       the Nixly panel profile this machine follows (desktop, laptop, htpc)
  local.nix     per-machine overrides and secrets (never in this repo)
  pins.nix      written by nixlyos-update: packages kept at their last
                working build because the newest failed to build
  meshy.key     Meshy.ai API key for the meshy CLI (mode 600)
  hardware/     data written by nixlyos-detect-hw + hardware-configuration.nix
```

## The panel decides

The Nixly panel (`../cachepanel`) owns what every setup runs. A machine follows a
*profile* (desktop, laptop, htpc, ...): the panel picks the nixlypkgs revision and
a profile tree with the selected modules from `catalog.nix`, panel modules and
packages from nixpkgs stable. Hardware modules stay automatic. The panel knows
profiles, never individual machines: `nixlyos-update` and `nixlyos-stage` pin
both through `nixlyos-panel`, and machines installed before the panel are
adopted on their next update. Without `profile` a machine follows `main`
exactly as before.

## Staged updates

A systemd timer (`nixlyos-stage`, hourly, idle priority, skipped under load
or on battery) builds the next generation in the background and keeps it
behind a GC root in `~/.local/state/nixlyos/stage`. `nixlyos-update` verifies
the staged build against a content key of the exact same inputs and then only
has to activate it — updates normally take seconds. On any mismatch it falls
back to a full parallel build, so the fast path can never activate a stale
system.

## Workflow

1. Commit on `main` (optionally `scripts/bump-inputs.sh` first), push.
2. The panel builds it, tests every type on `reference/profiles` and publishes.
3. `nixlyos-update` on any machine picks up its type's release.

## Layout

```
lib/mk-system.nix   mkNixlySystem: per-machine data + type tree -> complete NixOS system
catalog.nix        modules a type can select (apps/, services/)
reference/         hardware profiles every type is tested on
base/              everything that runs NixlyOS (boot, nix, session, sound, ...)
hardware/          cpu/, gpu/, machine profile - selected by nixlyos-detect-hw
services/          detect-activated extras (drawing tablets, on-demand, ...)
apps/              programs that ship preconfigured (steam, citrix, mpv, ...)
home/              home-manager entrypoint + per-app user config
pkgs/              brave, citrix, polkit-gnome overlays local to NixlyOS
scripts/           detect-hw, update, stage, panel (packaged as nixlyos-*
                   tools by base/nixlyos-tools.nix), bump-inputs (maintainer)
install.sh         installer: partitioning, LUKS2, ~/.local/nixlyos, nixos-install
wallpapers/
```

Hardware files are pure data (module *names* and numbers, never paths), so
generated files stay valid across NixlyOS versions.
