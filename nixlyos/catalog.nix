# Every NixlyOS module, in import order.
let
  both = [ "desktop" "htpc" ];
  desktop = [ "desktop" ];
  htpc = [ "htpc" ];
  unused = [ ];
in
[
  { name = "mode"; file = "base/mode.nix"; category = "system"; title = "Systemmodus"; profiles = both; required = true; }
  { name = "mode-switch"; file = "base/mode-switch.nix"; category = "system"; title = "Bytte mellom desktop og HTPC"; profiles = both; }
  { name = "input"; file = "base/input.nix"; category = "session"; title = "Mus og tastatur"; profiles = both; }
  { name = "distro"; file = "base/distro.nix"; category = "system"; title = "NixlyOS-identitet"; profiles = both; }
  { name = "boot"; file = "base/boot.nix"; category = "boot"; title = "Oppstart og kjerne"; profiles = both; required = true; }
  { name = "initrd-free"; file = "base/initrd-free.nix"; category = "boot"; title = "Frigjør initramfs etter oppstart"; profiles = both; }
  { name = "sddm"; file = "base/SDDM.nix"; category = "session"; title = "Innlogging (SDDM)"; profiles = both; }
  { name = "networking"; file = "base/networking.nix"; category = "network"; title = "Nettverk"; profiles = both; }
  { name = "shape"; file = "base/shape.nix"; category = "network"; title = "Køstyring mot WAN (cake)"; profiles = both; }
  { name = "speedtest"; file = "base/speedtest.nix"; category = "network"; title = "Måler linjehastighet ved oppstart"; profiles = both; }
  { name = "nic-latency"; file = "base/nic-latency.nix"; category = "network"; title = "Lav forsinkelse på nettverkskort"; profiles = both; }
  { name = "dns-ecs"; file = "base/dns-ecs.nix"; category = "network"; title = "DNS med lokasjon for strømming"; profiles = both; }
  { name = "tailscale"; file = "base/tailscale.nix"; category = "network"; title = "Tailscale ved behov"; profiles = both; }
  { name = "netbird"; file = "base/netbird.nix"; category = "network"; title = "NetBird ved behov"; profiles = both; }
  { name = "nix"; file = "base/nix.nix"; category = "system"; title = "Nix og binærcacher"; profiles = both; required = true; }
  { name = "project-roots"; file = "base/project-roots.nix"; category = "system"; title = "Beskytter ~/git-flakes mot GC"; profiles = both; }
  { name = "nfs"; file = "base/nfs.nix"; category = "network"; title = "NFS-deling"; profiles = both; }
  { name = "nfs-readahead"; file = "base/nfs-readahead.nix"; category = "network"; title = "NFS readahead"; profiles = both; }
  { name = "ssh"; file = "base/ssh.nix"; category = "network"; title = "SSH"; profiles = both; }
  { name = "gaming"; file = "apps/gaming.nix"; category = "gaming"; title = "Spill: Steam, Proton og GeForce NOW"; profiles = both; x86 = true; }
  { name = "boost"; file = "apps/boost/default.nix"; category = "gaming"; title = "Boost: full prioritet og dGPU"; profiles = both; x86 = true; }
  { name = "gametune"; file = "apps/gametune.nix"; category = "gaming"; title = "Automatisk spilljustering"; profiles = both; }
  { name = "packages"; file = "base/packages.nix"; category = "apps"; title = "Standardprogrammer"; profiles = both; }
  { name = "brave"; file = "apps/brave.nix"; category = "apps"; title = "Brave-nettleser"; profiles = both; }
  { name = "totalvim"; file = "apps/totalvim.nix"; category = "apps"; title = "Totalvim-editor"; profiles = both; }
  { name = "users"; file = "base/users.nix"; category = "system"; title = "Brukerkonto"; profiles = both; required = true; }
  { name = "timezone-locale"; file = "base/timezone_locale.nix"; category = "system"; title = "Tidssone og språk"; profiles = both; }
  { name = "system-services"; file = "base/system_services.nix"; category = "system"; title = "Systemtjenester"; profiles = both; }
  { name = "docs"; file = "base/docs.nix"; category = "system"; title = "Dokumentasjon av"; profiles = both; }
  { name = "perf"; file = "base/perf.nix"; category = "system"; title = "Ytelse og planlegging"; profiles = both; }
  { name = "prewarm"; file = "base/prewarm.nix"; category = "system"; title = "Forvarmer programmer i minnet"; profiles = both; x86 = true; }
  { name = "overhead"; file = "base/overhead.nix"; category = "system"; title = "Mindre bakgrunnsarbeid"; profiles = both; }
  { name = "wayland"; file = "base/wayland.nix"; category = "session"; title = "Wayland-økt"; profiles = both; }
  { name = "sound"; file = "base/sound.nix"; category = "session"; title = "Lyd (PipeWire)"; profiles = both; }
  { name = "mic"; file = "base/mic.nix"; category = "session"; title = "Mikrofonrensing"; profiles = both; }
  { name = "ptt"; file = "base/ptt.nix"; category = "session"; title = "Push-to-talk"; profiles = both; }
  { name = "voip"; file = "base/voip.nix"; category = "session"; title = "Push-to-mute for Discord"; profiles = both; }
  { name = "bluetooth"; file = "base/bluetooth.nix"; category = "session"; title = "Bluetooth"; profiles = both; }
  { name = "btpair"; file = "base/btpair/default.nix"; category = "session"; title = "Bluetooth-paring"; profiles = both; }
  { name = "zram"; file = "base/zram.nix"; category = "system"; title = "Komprimert minne (zram)"; profiles = both; }
  { name = "hibernate"; file = "base/hibernate.nix"; category = "boot"; title = "Dvale"; profiles = both; }
  { name = "security"; file = "base/security.nix"; category = "boot"; title = "Sikkerhetsinnstillinger"; profiles = both; }
  { name = "sandbox"; file = "base/sandbox.nix"; category = "boot"; title = "Sandkasse for programmer"; profiles = both; }
  { name = "attack-surface"; file = "base/attack-surface.nix"; category = "boot"; title = "Redusert angrepsflate"; profiles = both; }
  { name = "secureboot"; file = "base/secureboot.nix"; category = "boot"; title = "Secure Boot"; profiles = both; }
  { name = "ext4"; file = "base/ext4.nix"; category = "boot"; title = "ext4-filsystem"; profiles = both; }
  { name = "snapshots"; file = "base/snapshots.nix"; category = "boot"; title = "Øyeblikksbilder"; profiles = both; }
  { name = "keyring"; file = "base/keyring.nix"; category = "session"; title = "Nøkkelring"; profiles = both; }
  { name = "power"; file = "base/power.nix"; category = "system"; title = "Strømstyring"; profiles = both; }
  { name = "diskd"; file = "base/diskd.nix"; category = "system"; title = "Diskhendelser"; profiles = both; }
  { name = "jaild"; file = "base/jaild.nix"; category = "system"; title = "Isolerte programmer"; profiles = both; }
  { name = "disks-auto"; file = "base/disks-auto.nix"; category = "system"; title = "Automatisk montering"; profiles = both; }
  { name = "nixlyos-tools"; file = "base/nixlyos-tools.nix"; category = "system"; title = "NixlyOS-verktøy og oppdatering"; profiles = both; required = true; }
  { name = "update-stage"; file = "base/update-stage.nix"; category = "system"; title = "Bakgrunnsbygg av neste versjon"; profiles = both; }
  { name = "gpu-select"; file = "base/gpu-select.nix"; category = "session"; title = "Valg av GPU"; profiles = both; }
  { name = "nixlytile"; file = "base/nixlytile.nix"; category = "session"; title = "Nixlytile-skrivebord"; profiles = both; }
  { name = "newsboat"; file = "apps/newsboat.nix"; category = "apps"; title = "Newsboat RSS-leser"; profiles = both; }
  { name = "w3m"; file = "apps/w3m.nix"; category = "apps"; title = "w3m tekstnettleser"; profiles = both; }
  { name = "viewers"; file = "apps/viewers.nix"; category = "apps"; title = "Bildeviser"; profiles = both; }
  { name = "claude-thumbs"; file = "apps/claude-thumbs.nix"; category = "apps"; title = "Bildevarsler for Claude"; profiles = both; }
  { name = "pdf"; file = "apps/pdf.nix"; category = "apps"; title = "Nixly-PDF"; profiles = both; }
  { name = "calculator"; file = "apps/calculator.nix"; category = "apps"; title = "Kalkulator"; profiles = desktop; }
  { name = "freecad"; file = "apps/freecad.nix"; category = "apps"; title = "FreeCAD med MCP"; profiles = desktop; }
  { name = "mpv"; file = "apps/mpv.nix"; category = "apps"; title = "mpv videospiller"; profiles = both; }
  { name = "retroarch"; file = "apps/retroarch.nix"; category = "gaming"; title = "RetroArch"; profiles = desktop; }
  { name = "dgpu-apps"; file = "apps/dgpu-apps.nix"; category = "apps"; title = "Tunge programmer på dGPU"; profiles = both; }
  { name = "rom-playlists"; file = "apps/rom-playlists/default.nix"; category = "gaming"; title = "ROM-spillelister fra NFS"; profiles = both; }
  { name = "drawingtablet"; file = "services/drawingtablet.nix"; category = "services"; title = "Tegnebrett"; profiles = both; }
  { name = "citrix"; file = "apps/citrix.nix"; category = "apps"; title = "Citrix Workspace"; profiles = both; x86 = true; }
  { name = "ue5"; file = "apps/ue5.nix"; category = "apps"; title = "Unreal Engine 5"; profiles = both; x86 = true; }
  { name = "gaea"; file = "apps/gaea.nix"; category = "apps"; title = "Gaea terrengverktøy"; profiles = desktop; x86 = true; }
  { name = "dcspit"; file = "apps/dcspit.nix"; category = "gaming"; title = "DCS Pit"; profiles = both; }
  { name = "htpc-session"; file = "htpc/session.nix"; category = "htpc"; title = "HTPC-økt"; profiles = htpc; }
  { name = "htpc-media"; file = "htpc/media.nix"; category = "htpc"; title = "Media og emulering"; profiles = htpc; }
  { name = "htpc-audio"; file = "htpc/audio.nix"; category = "htpc"; title = "Lyd til TV og forsterker"; profiles = htpc; }
  { name = "htpc-hdmi-audio"; file = "htpc/hdmi-audio.nix"; category = "htpc"; title = "HDMI-lyd"; profiles = htpc; }
  { name = "htpc-bios-sync"; file = "htpc/bios-sync.nix"; category = "htpc"; title = "Delte BIOS-filer"; profiles = htpc; }
  { name = "htpc-retroarch-4k"; file = "htpc/retroarch-4k.nix"; category = "htpc"; title = "RetroArch i 4K"; profiles = htpc; }
  { name = "htpc-gpu-perf"; file = "htpc/gpu-perf.nix"; category = "htpc"; title = "Fast GPU-klokke"; profiles = htpc; }
  { name = "htpc-gpu-clock"; file = "htpc/gpu-clock.nix"; category = "htpc"; title = "GPU-klokke per program"; profiles = htpc; }
  { name = "htpc-auto-update"; file = "htpc/auto-update.nix"; category = "htpc"; title = "Nattlig oppdatering"; profiles = htpc; }
  { name = "htpc-prewarm"; file = "htpc/prewarm.nix"; category = "htpc"; title = "Forvarmede stueprogrammer"; profiles = htpc; }
  { name = "htpc-rom-cache"; file = "htpc/rom-cache.nix"; category = "htpc"; title = "Lokal ROM-cache"; profiles = htpc; }
  { name = "htpc-controllers"; file = "htpc/controllers.nix"; category = "htpc"; title = "Spillkontrollere"; profiles = htpc; }
  { name = "htpc-geforce-now"; file = "htpc/geforce-now.nix"; category = "htpc"; title = "GeForce NOW i stua"; profiles = htpc; }
  { name = "htpc-qos"; file = "htpc/qos.nix"; category = "htpc"; title = "Nettverksprioritet"; profiles = htpc; }
  { name = "htpc-rx-buffers"; file = "htpc/rx-buffers.nix"; category = "htpc"; title = "Mottaksbuffere"; profiles = htpc; }
  { name = "htpc-trim"; file = "htpc/trim.nix"; category = "htpc"; title = "Slankere bakgrunn"; profiles = htpc; }
  { name = "capture"; file = "base/capture.nix"; category = "session"; title = "Elgato-opptakskort"; profiles = both; }
  { name = "idle"; file = "base/idle.nix"; category = "session"; title = "Inaktivitet og lås"; profiles = both; }
  { name = "hardware-profile"; file = "hardware/profile.nix"; category = "hardware"; title = "Maskinprofil (nixos-hardware)"; profiles = both; required = true; }
  { name = "tablet"; file = "services/on-demand/tablet.nix"; category = "services"; title = "Tegnebrett ved behov"; profiles = both; }
  { name = "ollama"; file = "services/on-demand/ollama.nix"; category = "services"; title = "Ollama ved behov"; profiles = both; }
  { name = "strongswan"; file = "services/on-demand/strongswan.nix"; category = "services"; title = "strongSwan VPN ved behov"; profiles = both; }
  { name = "nixly-ai"; file = "services/nixly-ai/default.nix"; category = "services"; title = "Nixly AI-tjeneste"; profiles = unused; }
  { name = "appimage"; file = "apps/appimage.nix"; category = "apps"; title = "AppImage-støtte"; profiles = unused; }
  { name = "htpc-retroarch-full"; file = "htpc/retroarch-full.nix"; category = "htpc"; title = "RetroArch med alle kjerner"; profiles = unused; }
  { name = "htpc-steam-shortcuts"; file = "htpc/steam-shortcuts.nix"; category = "htpc"; title = "Steam-snarveier"; profiles = unused; }
  { name = "home-blender"; file = "home/blender_setup.nix"; category = "home"; title = "Blender-oppsett"; profiles = both; x86 = true; }
  { name = "home-git"; file = "home/git.nix"; category = "home"; title = "Git"; profiles = both; }
  { name = "home-bash"; file = "home/bash.nix"; category = "home"; title = "Bash"; profiles = both; }
  { name = "home-btop"; file = "home/btop.nix"; category = "home"; title = "btop"; profiles = both; }
  { name = "home-starship"; file = "home/starship.nix"; category = "home"; title = "Starship-ledetekst"; profiles = both; }
  { name = "home-alacritty"; file = "home/alacritty.nix"; category = "home"; title = "Alacritty"; profiles = both; }
  { name = "home-foot"; file = "home/foot.nix"; category = "home"; title = "foot-terminal"; profiles = both; }
  { name = "home-fuzzel"; file = "home/fuzzel.nix"; category = "home"; title = "Fuzzel-oppstarter"; profiles = both; }
  { name = "home-theme"; file = "home/nixly-theme.nix"; category = "home"; title = "Nixly-tema"; profiles = both; }
  { name = "home-nixlytile"; file = "home/nixlytile.nix"; category = "home"; title = "Nixlytile-oppsett"; profiles = both; }
  { name = "home-env"; file = "home/env.nix"; category = "home"; title = "Miljøvariabler"; profiles = both; }
  { name = "home-gtk"; file = "home/gtk.nix"; category = "home"; title = "GTK-tema"; profiles = both; }
  { name = "home-qt"; file = "home/qt.nix"; category = "home"; title = "Qt-tema"; profiles = both; }
  { name = "home-emulators"; file = "home/emulator_config.nix"; category = "home"; title = "Emulatoroppsett"; profiles = both; }
  { name = "home-audio-priority"; file = "home/audio_priority.nix"; category = "home"; title = "Lydprioritet"; profiles = both; }
  { name = "home-caveman"; file = "home/caveman.nix"; category = "home"; title = "Caveman for Claude"; profiles = both; }
  { name = "home-claude"; file = "home/claude.nix"; category = "home"; title = "Claude Code"; profiles = both; }
  { name = "home-meshy"; file = "home/meshy.nix"; category = "home"; title = "Meshy"; profiles = both; }
  { name = "home-discord-rpc"; file = "home/discord_rpc.nix"; category = "home"; title = "Discord-status"; profiles = both; }
  { name = "home-clipman"; file = "home/clipman.nix"; category = "home"; title = "Utklippshistorikk"; profiles = unused; }
  { name = "home-nautilus"; file = "home/nautilus.nix"; category = "home"; title = "Nautilus"; profiles = unused; }
]
