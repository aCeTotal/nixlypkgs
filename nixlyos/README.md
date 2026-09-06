# NixlyOS

The whole NixlyOS system, built from this repo via `lib.mkNixlySystem`.
Machines carry no configuration tree — only `~/.local/nixlyos`:

```
~/.local/nixlyos/
  flake.nix     tiny; points at nixlypkgs (main)
  flake.lock    the machine's pin — updates only via nixlyos-update
  local.nix     per-machine overrides and secrets (never in this repo)
  hardware/     data written by nixlyos-detect-hw + hardware-configuration.nix
```

## Branch

Everything tracks `main` while the system is under active development.
This repo`s `flake.lock` is THE system pin: machines only ever run
`nix flake update nixlypkgs`, so every input (nixpkgs, chaotic kernel,
home-manager, ...) arrives exactly as pinned - never "latest at update time".
Release/testing channels can be reintroduced later by branching and pointing
machine flakes at the branch.

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
2. `nixlyos-update` on any machine picks it up.

## Layout

```
lib/mk-system.nix   mkNixlySystem: per-machine data -> complete NixOS system
base/              everything that runs NixlyOS (boot, nix, session, sound, ...)
hardware/          cpu/, gpu/, machine profile - selected by nixlyos-detect-hw
services/          detect-activated extras (drawing tablets, on-demand, ...)
apps/              programs that ship preconfigured (steam, citrix, mpv, ...)
home/              home-manager entrypoint + per-app user config
pkgs/              chrome + citrix overlays local to NixlyOS
scripts/           detect-hw, update, stage, (packaged as nixlyos-*
                   tools by base/nixlyos-tools.nix), bump-inputs (maintainer)
install.sh         installer: partitioning, LUKS2, ~/.local/nixlyos, nixos-install
wallpapers/
```

Hardware files are pure data (module *names* and numbers, never paths), so
generated files stay valid across NixlyOS versions.
