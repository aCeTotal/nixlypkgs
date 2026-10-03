# NixlyServer

Headless, hardened NixOS server built from this repo via `lib.mkNixlyServer`.
No GUI; a web panel will own the settings in `options.nix`.

## Machine

Each server carries only `/etc/nixlyserver` (root-owned):

```nix
# /etc/nixlyserver/flake.nix
{
  inputs.nixlypkgs.url = "github:aCeTotal/nixlypkgs";
  outputs = { nixlypkgs, ... }: {
    nixosConfigurations.<hostname> = nixlypkgs.lib.mkNixlyServer {
      hostName = "<hostname>";
      stateVersion = "26.05";
      hardwareDir = ./hardware;     # hardware-configuration.nix
      username = "total";
      sshKeys = [ "ssh-ed25519 ..." ];
      # biosBootDevice = "/dev/vda"; # legacy-BIOS VMs only
      localConfig = ./local.nix;    # optional
    };
  };
}
```

UEFI installs need Secure Boot keys before the first switch (`sbctl create-keys`,
then `sbctl enroll-keys --microsoft` in setup mode), and the LUKS root bound to
the TPM once Secure Boot is on:

```
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/root
```

## Defaults

| Setting | Default | Alternatives |
|---|---|---|
| `nixlyserver.access` | `lan`: SSH from LAN and tailnet | `vpn`: tailnet only |
| `nixlyserver.updates` | `auto-reboot`: nightly, reboots on kernel change | `auto`, `manual` |
| `nixlyserver.allowedCountries` | NATO members | any ISO 3166 codes |

## Layout

```
mk-server.nix   machine data -> NixOS system
kernel.nix      boot params, sysctl, module lock (build: pkgs/linux-nixlyserver)
boot.nix        lanzaboote, TPM2 unlock, boot counting with health gate
ingress/        country allowlist, VPN/hosting/Tor denylist, SSH flood bans
access.nix      sshd and tailscale, per access mode
recovery.nix    watchdog, panic reboot
network.nix     networkd, DNS over TLS, NTS time
updates.nix     nightly upgrade from the nixlypkgs pin
users.nix       key-only admin, sudo-rs
nix.nix         daemon access and caches
audit.nix       auditd watches
headless.nix    no desktop plumbing, persistent journal
```
