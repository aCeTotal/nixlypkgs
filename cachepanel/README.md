# Nixly Panel

Control panel for nixlypkgs and every NixlyOS setup: the binary cache, profiles, the module registry and
the package wizard. The panel knows profiles, never individual machines.

- **Cache** – every commit on the branch is evaluated; each derivation keeps its three newest versions in
  a signed file cache the panel serves itself (`cache.dir`, put it on a big disk); the Nix store is only
  build space. Older versions are garbage collected. Any version can be selected, rebuilt, cancelled or
  deleted, with live progress and logs.
- **Profiles** – Desktop, Laptop, HTPC and your own. A profile is the required modules plus its chosen
  ones, packages from nixpkgs stable (nixlypkgs on top) and a nixlypkgs revision. The hardware module
  picks drivers on each machine. Machines pull their profile's release with ETags; trees are
  content-addressed and CDN-cacheable.
- **Modules** – every NixlyOS module lives in the database with its revisions: a matrix shows which
  profile uses what, and the editor has an outline of each module's sections, search, folding and
  inline syntax errors.
- **Trust** – every change to a profile is evaluated *and built* on all reference hardware before it
  reaches the **testing** branch. **Stable**, which machines follow by default, moves only when you
  approve testing on its own page, for every profile at once. Machines only ever receive tested releases.
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
  cache.dir = "/mnt/bigdisk2/nixlyos/cache";
  cache.publicKey = "cache.aceclan.no-1:…";   # the server substitutes from its own cache
};
```

The module sets up PostgreSQL, the panel service (unprivileged, sandboxed), the cache signed with the
existing `cache.aceclan.no-1` key, Caddy with HTTPS and a deploy key for the wizard; the panel shows its
public half under Add derivation → Publish, to be added on GitHub with write access. It replaces the old
nixlycaching watcher. Change the password under the user menu after the first login.

## Layout

| Path | Contents |
|---|---|
| `server/<feature>` | Go backend, one package per feature (`builds`, `watcher`, `profiles`, `wizard`, …) |
| `server/recipe`, `server/analyse`, `server/pkgbuild`, `server/depmap` | Wizard internals: Nix generation, source analysis, PKGBUILD reading, nixpkgs name tables |
| `server/migrations` | SQL migrations; `00005_modules.sql` seeds the NixlyOS modules on fresh installs |
| `web/src/<feature>` | React frontend, one folder per feature; `web/src/ui` is the shadcn/ui kit |
| `web/src/modules/nix` | Nix grammar for the editor, compiled by `@lezer/generator` at build time |
| `nix` | Package, NixOS module, dev stack, demo repository and VM test |

Machines talk to the panel through `nixlyos-panel` (`nixlyos/scripts/panel.sh`).
