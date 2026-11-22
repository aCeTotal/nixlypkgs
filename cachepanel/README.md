# Nixly Panel

Control panel for nixlypkgs and every NixlyOS setup: the binary cache, profiles, the module registry and
the package wizard. The panel knows profiles, never individual machines.

- **Cache** – every commit on the branch is evaluated; each package keeps its three newest derivations
  built and served by harmonia. Older ones are garbage collected. Any version can be selected, rebuilt,
  cancelled or deleted, with live progress and logs.
- **Profiles** – Desktop, Laptop, HTPC and your own. A profile is a set of registry and panel modules,
  packages from nixpkgs stable (nixlypkgs on top) and a nixlypkgs revision. Hardware modules are chosen on
  each machine automatically. Machines pull their profile's release with ETags; trees are
  content-addressed and CDN-cacheable.
- **Modules** – every NixlyOS module in nixlypkgs, sorted into categories, plus modules written in the
  panel.
- **Trust** – every change to a profile is evaluated *and built* on all reference hardware before it is
  published. Machines only ever receive tested releases.
- **Package wizard** – new nixlypkgs packages from a link, an upload, a GitHub repo or a PKGBUILD from
  Arch or the AUR. It finds the build system and dependencies, test-builds in the sandbox, fixes what
  the log explains (hashes, missing libraries, tools, headers, toolchains) and commits the result to
  `pkgs/<attr>`. PKGBUILDs run through `buildArchPackage`, a makepkg emulation in Nix.

## Run locally

```sh
nix run      # PostgreSQL + panel against a demo repository, opens http://localhost:8686
nix develop  # Go, Node, PostgreSQL, nix-eval-jobs, nixfmt
nix flake check   # NixOS VM test of the whole flow
```

Log in with `nixlyos` / `nixos`. Set `CACHEPANEL_REPOSITORY=https://github.com/aCeTotal/nixlypkgs` to
follow the real repository, or `CACHEPANEL_DEMO_PACKAGES=path:/path/to/nixlypkgs` to give the demo
repository a real package set for the wizard. Inside `nix develop`, `cd web && npm run dev` gives hot
reload against :8686.

`CACHEPANEL_PROGRAMS=<flake ref> go test ./wizard -run TestPrograms` imports and builds 38 real programs
(every builder and source type) and runs each one.

## Deploy

```nix
# flake inputs: nixlypkgs.url = "github:aCeTotal/nixlypkgs";
imports = [ nixlypkgs.nixosModules.cachepanel ];
services.nixly-cachepanel = {
  enable = true;
  domain = "cache.aceclan.no";   # HTTPS via Caddy: panel, machine API and binary cache
};
```

The module sets up PostgreSQL, the panel service (unprivileged, sandboxed), harmonia with the existing
`cache.aceclan.no-1` key, Caddy with HTTPS and a deploy key for the wizard; the panel shows its public half
under Nye pakker → Publiser, to be added on GitHub with write access. It replaces the old nixlycaching
watcher. Change the password under the user menu after the first login.

## Layout

| Path | Contents |
|---|---|
| `server/<feature>` | Go backend, one package per feature (`builds`, `watcher`, `profiles`, `wizard`, …) |
| `server/recipe`, `server/analyse`, `server/pkgbuild`, `server/depmap` | Wizard internals: Nix generation, source analysis, PKGBUILD reading, nixpkgs name tables |
| `server/migrations` | SQL migrations |
| `web/src/<feature>` | React frontend, one folder per feature; `web/src/ui` is the shadcn/ui kit |
| `nix` | Package, NixOS module, dev stack, demo repository and VM test |

Machines talk to the panel through `nixlyos-panel` (`nixlyos/scripts/panel.sh`).
