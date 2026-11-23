# NixlyOS

The whole NixlyOS system, built via `lib.mkNixlySystem` from this repo and a
profile tree published by the Nixly panel. Machines carry no configuration
tree — only `~/.local/nixlyos`:

```
~/.local/nixlyos/
  flake.nix     tiny; nixlypkgs revision and profile tree pinned by the panel
  flake.lock    the machine's pin — updates only via nixlyos-update
  profile       the Nixly panel profile this machine follows (desktop, laptop, htpc)
  branch        stable (default) or testing, set by nixlyos-panel branch
  local.nix     per-machine overrides and secrets (never in this repo)
  meshy.key     Meshy.ai API key for the meshy CLI (mode 600)
  hardware/     data written by nixlyos-detect-hw + hardware-configuration.nix
```

## The panel decides

Every NixlyOS module lives in the Nixly panel's database (`../cachepanel`),
not in this repo. A machine follows a *profile* (desktop, laptop, htpc, ...):
the panel publishes the nixlypkgs revision together with a profile tree that
holds the required modules, the modules the profile selected and its extra
packages. The hardware module picks CPU, GPU and guest support from
`nixlyos-detect-hw`. The panel knows profiles, never individual machines:
`nixlyos-update` and `nixlyos-stage` pin both through `nixlyos-panel`, and
machines installed before the panel are adopted on their next update.
`nixlyos-panel use htpc` moves a machine to another profile from its next
update.

Each profile has two branches. Everything new — commits, module and profile
edits — lands in **testing** once it builds on all reference hardware;
**stable** moves only when testing is approved in the panel, for all profiles
at once. Machines follow stable; `nixlyos-panel branch testing` (and back
with `stable`) switches one from its next update.

Machines never compile: both commands install only the profile's published
release and fetch every package from the cache. If anything would need a
source build, the update stops before touching the machine; only
machine-specific glue (initrd, units, config files) is built locally.

## Staged updates

A systemd timer (`nixlyos-stage`, hourly, idle priority, skipped under load
or on battery) builds the next generation in the background and keeps it
behind a GC root in `~/.local/state/nixlyos/stage`. `nixlyos-update` verifies
the staged build against a content key of the exact same inputs and then only
has to activate it — updates normally take seconds. On any mismatch it fetches
the release itself, so the fast path can never activate a stale system.

## Workflow

1. Change modules in the panel, or packages here (commit on `main`,
   optionally `scripts/bump-inputs.sh` first) and push.
2. The panel builds it, tests every profile on `reference/profiles` and puts
   it in testing; approve it in the panel to make it stable.
3. `nixlyos-update` on any machine picks up its profile's release on its branch.

## Layout

```
lib/mk-system.nix   mkNixlySystem: machine data + profile tree -> complete NixOS system
reference/          hardware profiles every profile is tested on
scripts/            detect-hw, update, stage, panel and user-config, packaged as
                    nixlyos-* commands by scripts/overlay.nix; bump-inputs (maintainer)
pkgs/               brave and polkit-gnome overlays local to NixlyOS
install.sh          installer: partitioning, LUKS2, ~/.local/nixlyos, nixos-install
```

Hardware files are pure data (module *names* and numbers, never paths), so
generated files stay valid across NixlyOS versions.
