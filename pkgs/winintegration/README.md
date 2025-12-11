winintegration
================

High-performance Windows 11 VM integration via libvirt/qemu/KVM with RDP/RemoteApp helpers for per-window tiling on Hyprland.

Build
- nix build .#winintegration

Prereqs (NixOS)
- virtualisation.libvirtd.enable = true
- programs.virt-manager.enable = true (optional)
- user in groups: libvirt, kvm

Install flow
- winintegration download-iso
- winintegration define-install
- winintegration start
- winintegration viewer (follow installer)
- After install: winintegration eject-iso && winintegration define

Guest steps for integration
- From virtio-win ISO: install virtio drivers, QEMU Guest Agent, Spice Guest Tools
- Enable Remote Desktop in Windows
- Virtiofs host share appears as hostshare once virtiofs driver is installed

Hyprland per-window
- Full desktop: winintegration rdp
- RemoteApp: winintegration rdp-app "||Explorer" (or other apps)

Env overrides
- WIN_ISO_URL, WIN_ISO_FILE
- WIN_HOST_SHARE_DIR (default: ~/Share/win)
- RDP_USER, RDP_PASS
- WIN_VM_NAME (default: winintegration)
- WIN_VM_MAX_MEM_MIB (default: 8000)
- WIN_VM_MIN_MEM_MIB (default: 1000)

Memory notes
- The domain uses max memory = WIN_VM_MAX_MEM_MIB and sets a minimum (floor) via memtune = WIN_VM_MIN_MEM_MIB.
- currentMemory equals max so the guest sees full RAM; QEMU allocates lazily so unused RAM isn’t hogged. Ballooning can reclaim memory if the host directs it.
- A virtio memballoon is present; install the VirtIO Balloon driver in Windows for best results.
- Hugepages are disabled to avoid preallocation; memory is demand-allocated by QEMU.
