# Nixly Panel

Control panel for nixlypkgs and every NixlyOS setup: the binary cache, profiles, the module registry and
the package wizard. The panel knows profiles, never individual machines.

- **Source** – nixlypkgs lives in the panel as its own git repository, seeded once from GitHub. Keys
  added under Source push over SSH, or edit any file in the panel's editor with history, diffs and revert;
  anyone clones over HTTPS and machines lock each release from it. History only moves forward.
- **Cache** – every commit on the branch is evaluated; each derivation keeps its three newest versions in
  a signed file cache the panel serves itself (`cache.dir`, put it on a big disk); the Nix store is only
  build space. Older versions are garbage collected. Any version can be selected, rebuilt, cancelled or
  deleted, with live progress and logs.
- **Upstream** – a derivation with `pkgs/<attr>/source.json` follows its repository: every commit on a
  branch, or the newest numeric tag. Each minute the panel pins what moved (rev, hash, version and vendored
  hashes such as `cargoHash`) in one commit on main, listing the upstream commits. Testing builds it; each
  derivation still reaches stable only when you approve it, and a newer pin replaces one still waiting.
- **Profiles** – Desktop, HTPC, Server and your own. A profile is the required modules plus its chosen
  ones, packages from nixpkgs stable (nixlypkgs on top), a nixlypkgs revision and a kernel from the
  source's catalogue with its own settings: tick rate, idle ticks, preemption, huge pages, TCP and the
  scheduler. Only tick changes rebuild the kernel. The hardware module picks drivers on each machine.
  Each is `nixlyos/profiles/<name>.json` in the source, so every edit is a commit with a message, from
  the panel or over SSH. Machines pull their profile's release with ETags; trees are content-addressed
  and CDN-cacheable.
- **Modules** – every NixlyOS module is a file in `nixlyos/modules`, listed in `catalogue.json` in import
  order; saving commits it and its history is git's. A matrix shows which profile uses what, and the
  editor has an outline of each module's sections, search, folding and inline syntax errors.
- **Testing** – every change to a profile is evaluated *and built* on all reference hardware before it
  reaches the **testing** branch. Each release passes only once every path of its systems, nixpkgs
  included, has a narinfo in the panel's cache; the panel records the count and size. **Stable**, which
  machines follow by default, moves only when you approve testing on its own page, for every profile at
  once, and its check proves the cache again. Machines only ever receive tested, fully cached releases.
- **Trust** – the NixlyOS CA lives on the server, its key readable by the panel alone. Releases that pass
  are signed (kernels, modules, systemd-boot), firmware key updates come signed from the panel, and the
  Easy Anti-Cheat bundle holds the CA and the policy Epic reviews.
- **Package wizard** – new nixlypkgs packages from a link, an upload, a GitHub repo or a PKGBUILD from
  Arch or the AUR. It finds the build system and dependencies, test-builds in the sandbox, fixes what
  the log explains (hashes, missing libraries, tools, headers, toolchains) and commits the result to
  `pkgs/<attr>`; a GitHub package gets its `source.json` and follows its releases or branch from then on.
  PKGBUILDs run through `buildArchPackage`, a makepkg emulation in Nix.

## Run locally

```sh
nix run      # PostgreSQL + panel against a demo repository, opens http://localhost:8686
nix develop  # Go, Node, PostgreSQL, nix-eval-jobs, nixfmt
nix flake check   # NixOS VM test of the whole flow
```

Log in with `nixlyos` / `nixos`. Set `CACHEPANEL_SOURCE_SEED=https://github.com/aCeTotal/nixlypkgs` before
the first start to seed the source from the real repository, or `CACHEPANEL_DEMO_PACKAGES=path:/path/to/nixlypkgs` to give the demo
repository a real package set for the wizard. Inside `nix develop`, `cd web && npm run dev` gives hot
reload against :8686.

`CACHEPANEL_PROGRAMS=<flake ref> go test ./wizard -run TestPrograms` imports and builds 38 real programs
(every builder and source type) and runs each one.

## Deploy

```nix
# flake inputs: nixlypkgs.url = "git+file:///var/lib/cachepanel/source.git";
imports = [ nixlypkgs.nixosModules.cachepanel ];
services.nixly-cachepanel = {
  enable = true;
  domain = "cache.aceclan.no";   # HTTPS via Caddy: panel, machine API and binary cache
  cache.dir = "/mnt/bigdisk2/nixlyos/cache";
  cache.publicKey = "cache.aceclan.no-1:…";   # the server substitutes from its own cache
};
```

The module sets up PostgreSQL, the panel service (unprivileged, sandboxed), the cache signed with the
existing `cache.aceclan.no-1` key, Caddy with HTTPS and SSH push for `cachepanel@<domain>:source.git`.
It replaces the old nixlycaching watcher. Change the password under the user menu after the first login.

## Layout

| Path | Contents |
|---|---|
| `server/<feature>` | Go backend, one package per feature (`builds`, `watcher`, `profiles`, `wizard`, …) |
| `server/recipe`, `server/analyse`, `server/pkgbuild`, `server/depmap` | Wizard internals: Nix generation, source analysis, PKGBUILD reading, nixpkgs name tables |
| `server/migrations` | SQL migrations, applied in order |
| `web/src/<feature>` | React frontend, one folder per feature; `web/src/ui` is the shadcn/ui kit |
| `web/src/modules/nix` | Nix grammar for the editor, compiled by `@lezer/generator` at build time |
| `nix` | Package, NixOS module, dev stack, demo repository and VM test |

Machines talk to the panel through `nixlyos-panel` (`nixlyos/scripts/panel.sh`).
