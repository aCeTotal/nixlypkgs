{ lib
, stdenvNoCC
, fetchzip
, makeWrapper
, qemu
, libvirt
, virt-install
, edk2-ovmf
, virtio-win
, unzip
, coreutils
, util-linux
, findutils
, freerdp3
, curl
, virt-viewer
}:

stdenvNoCC.mkDerivation rec {
  pname = "winintegration";
  version = "0.1.0";

  # No external payload by default (avoid network); create empty store file
  src = builtins.toFile "payload-empty" "";

  dontBuild = true;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/winintegration $out/bin

    # Prepare optional payload dir (empty by default; no network fetch)
    mkdir -p "$out/share/winintegration/payload"

    # Main orchestrator
    cat > $out/bin/winintegration <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

VM_NAME="''${WIN_VM_NAME:-winintegration}"
CONN="''${LIBVIRT_DEFAULT_URI:-qemu:///session}"

XDG_DATA_HOME_DEFAULT="$HOME/.local/share"
XDG_STATE_HOME_DEFAULT="$HOME/.local/state"
XDG_CONFIG_HOME_DEFAULT="$HOME/.config"

DATA_DIR="''${XDG_DATA_HOME:-$XDG_DATA_HOME_DEFAULT}/winintegration"
STATE_DIR="''${XDG_STATE_HOME:-$XDG_STATE_HOME_DEFAULT}/winintegration"
CONF_DIR="''${XDG_CONFIG_HOME:-$XDG_CONFIG_HOME_DEFAULT}/winintegration"

PAYLOAD_DIR="''${WININTEGRATION_PAYLOAD_DIR:-}"

# Default Windows 11 ISO source (can be overridden)
WIN_ISO_URL_DEFAULT="https://pfoprod.ddns.net/Adrian/nixly_win11.iso"
WIN_ISO_PATH_DEFAULT="$DATA_DIR/win11.iso"

# Optional host share directory (virtiofs)
HOST_SHARE_DIR_DEFAULT="''${WIN_HOST_SHARE_DIR:-$HOME/Share/win}"

mkdir -p "$DATA_DIR" "$STATE_DIR" "$CONF_DIR"

die() { echo "error: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

find_ovmf() {
  # Resolve OVMF paths from EDK2_OVMF (provided by wrapper)
  local base="''${EDK2_OVMF:-}"
  [ -n "$base" ] || die "EDK2_OVMF env not set (wrapper bug)"
  local code vars
  code=$(find "$base" -type f -name 'OVMF_CODE*.fd' | head -n1 || true)
  vars=$(find "$base" -type f -name 'OVMF_VARS*.fd' | head -n1 || true)
  [ -n "$code" ] || die "Could not find OVMF_CODE.fd in $base"
  [ -n "$vars" ] || die "Could not find OVMF_VARS.fd in $base"
  echo "$code|$vars"
}

find_virtio_win_iso() {
  # Optional: virtio-win ISO for drivers
  local base="''${VIRTIO_WIN:-}"
  [ -n "$base" ] || return 0
  local iso
  iso=$(find "$base" -type f -name '*.iso' | head -n1 || true)
  [ -n "$iso" ] || return 0
  echo "$iso"
}

resolve_win_iso_path() {
  # Priority: WIN_ISO_FILE env -> config -> default path if file exists
  if [ -n "''${WIN_ISO_FILE:-}" ] && [ -f "''${WIN_ISO_FILE}" ]; then
    echo "''${WIN_ISO_FILE}"
    return 0
  fi
  if [ -f "$CONF_DIR/win-iso.path" ]; then
    local p
    p=$(cat "$CONF_DIR/win-iso.path")
    if [ -f "$p" ]; then
      echo "$p"; return 0
    fi
  fi
  if [ -f "$WIN_ISO_PATH_DEFAULT" ]; then
    echo "$WIN_ISO_PATH_DEFAULT"; return 0
  fi
  return 1
}

resolve_win_iso_url() {
  # Priority: WIN_ISO_URL env -> config -> default URL
  if [ -n "''${WIN_ISO_URL:-}" ]; then echo "''${WIN_ISO_URL}"; return 0; fi
  if [ -f "$CONF_DIR/win-iso.url" ]; then cat "$CONF_DIR/win-iso.url"; return 0; fi
  echo "$WIN_ISO_URL_DEFAULT"
}

host_cpus() {
  local n
  if command -v nproc >/dev/null 2>&1; then n=$(nproc); else n=4; fi
  echo "$n"
}

host_mem_mib() {
  # Return MemTotal in MiB
  awk '/MemTotal:/ { print int($2/1024) }' /proc/meminfo 2>/dev/null || echo 8192
}

ensure_disk() {
  local disk="$DATA_DIR/win.qcow2"
  if [ -f "$disk" ]; then
    echo "$disk"
    return 0
  fi
  # If payload contains a qcow2, copy it in
  if [ -n "$PAYLOAD_DIR" ] && [ -d "$PAYLOAD_DIR" ]; then
    local found
    found=$(find "$PAYLOAD_DIR" -maxdepth 2 -type f \( -iname '*.qcow2' -o -iname '*.qcow' \) | head -n1 || true)
    if [ -n "$found" ]; then
      echo "Using QCOW2 from payload: $found"
      cp -f "$found" "$disk"
      echo "$disk"
      return 0
    fi
  fi
  # Otherwise create a new thin-provisioned disk (100 GiB)
  echo "Creating new disk: $disk"
  qemu-img create -f qcow2 "$disk" 100G >/dev/null
  echo "$disk"
}

compose_domain_xml() {
  local cpus total_mem mem guest_mem iothreads
  cpus=$(host_cpus)
  total_mem=$(host_mem_mib)
  # Heuristics: reserve 2 CPUs for host
  [ "$cpus" -gt 2 ] && cpus=$((cpus-2)) || cpus=2

  # Memory policy:
  # - Max 8000 MiB, Min 1000 MiB by default (overridable via env)
  # - We set currentMemory to max so guest sees full RAM, but avoid hogging
  #   via lazy allocation and optional ballooning; min is expressed via memtune.
  # - Clamp to host memory - 512 MiB minimum safety margin
  local mem_max mem_min host_limit
  mem_max="''${WIN_VM_MAX_MEM_MIB:-8000}"
  mem_min="''${WIN_VM_MIN_MEM_MIB:-1000}"
  host_limit=$(( total_mem - 512 ))
  if [ "$host_limit" -lt 1024 ]; then host_limit=1024; fi
  # Clamp max to host_limit and at least 1024
  if [ "$mem_max" -gt "$host_limit" ]; then mem_max=$host_limit; fi
  if [ "$mem_max" -lt 1024 ]; then mem_max=1024; fi
  # Clamp min between 512 and mem_max
  if [ "$mem_min" -lt 512 ]; then mem_min=512; fi
  if [ "$mem_min" -gt "$mem_max" ]; then mem_min=$mem_max; fi
  iothreads=1

  local ovmf ovmf_code ovmf_vars vars_copy
  ovmf=$(find_ovmf)
  ovmf_code="''${ovmf%|*}"; ovmf_vars="''${ovmf#*|}"
  vars_copy="$DATA_DIR/OVMF_VARS_''${VM_NAME}.fd"
  if [ ! -f "$vars_copy" ]; then
    cp -f "$ovmf_vars" "$vars_copy"
  fi

  local disk; disk=$(ensure_disk)
  local virtio_iso; virtio_iso=$(find_virtio_win_iso || true)
  local win_iso=""; win_iso=$(resolve_win_iso_path || true)

  # virtiofs share for payload if present
  local fs_xml=""; local fs_target="winintegration"
  if [ -n "$PAYLOAD_DIR" ] && [ -d "$PAYLOAD_DIR" ]; then
    fs_xml="\n    <filesystem type='mount' accessmode='passthrough'>\n      <driver type='virtiofs'/>\n      <source dir='$PAYLOAD_DIR'/>\n      <target dir='$fs_target'/>\n    </filesystem>"
  fi

  # Optional host share directory
  if [ -d "$HOST_SHARE_DIR_DEFAULT" ]; then
    fs_xml+="\n    <filesystem type='mount' accessmode='passthrough'>\n      <driver type='virtiofs'/>\n      <source dir='$HOST_SHARE_DIR_DEFAULT'/>\n      <target dir='hostshare'/>\n    </filesystem>"
  fi

  local cdrom_virtio=""
  if [ -n "$virtio_iso" ]; then
    cdrom_virtio="\n    <disk type='file' device='cdrom'>\n      <driver name='qemu' type='raw'/>\n      <source file='$virtio_iso'/>\n      <target dev='sdc' bus='sata'/>\n      <readonly/>\n    </disk>"
  fi

  local cdrom_winiso=""
  if [ -n "$win_iso" ] && [ -f "$win_iso" ]; then
    cdrom_winiso="\n    <disk type='file' device='cdrom'>\n      <driver name='qemu' type='raw'/>\n      <source file='$win_iso'/>\n      <target dev='sdb' bus='sata'/>\n      <readonly/>\n    </disk>"
  fi

  cat > "$CONF_DIR/''${VM_NAME}.xml" <<XML
<domain type='kvm'>
  <name>''${VM_NAME}</name>
  <memory unit='MiB'>''${mem_max}</memory>
  <currentMemory unit='MiB'>''${mem_max}</currentMemory>
  <vcpu placement='static'>''${cpus}</vcpu>
  <iothreads>''${iothreads}</iothreads>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>''${ovmf_code}</loader>
    <nvram>''${vars_copy}</nvram>
    <boot dev='hd'/>
    <bootmenu enable='yes'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <vmport state='off'/>
    <kvm>
      <hidden state='on'/>
    </kvm>
    <hyperv>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vpindex state='on'/>
      <runtime state='on'/>
      <synic state='on'/>
      <stimer state='on'/>
      <reset state='on'/>
      <!-- vendor_id must be exactly 12 ASCII chars -->
      <vendor_id state='on' value='KVMNvrdia01'/>
      <frequencies state='on'/>
      <reenlightenment state='on'/>
    </hyperv>
  </features>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' dies='1' cores='$cpus' threads='1'/>
  </cpu>
  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='hpet' present='no'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hypervclock' present='yes'/>
  </clock>
  <!-- Avoid hugepages so memory is demand-allocated and balloon-friendly -->
  <memoryBacking/>
  <memtune>
    <min_guarantee unit='MiB'>''${mem_min}</min_guarantee>
  </memtune>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none' io='native' discard='unmap'/>
      <source file='$disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>''${cdrom_winiso}''${cdrom_virtio}
    <controller type='pci' model='pcie-root'/>
    <controller type='sata' index='0'/>
    <controller type='usb' model='qemu-xhci'/>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <input type='tablet' bus='usb'/>
    <sound model='ich9'/>
    <video>
      <model type='virtio' heads='1'/>
    </video>
    <tpm model='tpm-tis'>
      <backend type='emulator' version='2.0'/>
    </tpm>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
    </rng>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
    </channel>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
    <memballoon model='virtio'>
      <stats period='10'/>
    </memballoon>
    <graphics type='spice' autoport='yes' listen='127.0.0.1'>
      <image compression='off'/>
    </graphics>''${fs_xml}
  </devices>
</domain>
XML
}

cmd_init() {
  echo "==> Preparing payload and data dirs"
  if [ -n "$PAYLOAD_DIR" ] && [ -d "$PAYLOAD_DIR" ]; then
    echo "Payload available at: $PAYLOAD_DIR"
  else
    echo "No payload directory is embedded; replace placeholder in derivation."
  fi
  ensure_disk >/dev/null
  echo "OK"
}

cmd_define() {
  echo "==> Composing domain XML"
  compose_domain_xml
  echo "==> Defining domain $VM_NAME"
  virsh --connect "$CONN" define "$CONF_DIR/''${VM_NAME}.xml" >/dev/null
  echo "Defined: $VM_NAME"
}

cmd_define_install() {
  echo "==> Composing domain XML (install mode)"
  compose_domain_xml
  # Force boot from CDROM for first install boot
  # Modify a temp XML to prefer CDROM
  local tmp
  tmp=$(mktemp)
  sed "s#<boot dev='hd'/>#<boot dev='cdrom'/>#" "$CONF_DIR/''${VM_NAME}.xml" > "$tmp"
  echo "==> Defining domain $VM_NAME (install)"
  virsh --connect "$CONN" define "$tmp" >/dev/null
  rm -f "$tmp"
  echo "Defined (install): $VM_NAME"
}

cmd_start() {
  virsh --connect "$CONN" start "$VM_NAME" || true
  echo "VM started (or already running)."
}

cmd_autostart_on() {
  virsh --connect "$CONN" autostart "$VM_NAME"
}

cmd_autostart_off() {
  virsh --connect "$CONN" autostart --disable "$VM_NAME"
}

cmd_viewer() {
  # Use virt-viewer for SPICE display
  exec virt-viewer -c "$CONN" "$VM_NAME"
}

vm_ip() {
  # Try guest agent first
  if virsh --connect "$CONN" domifaddr "$VM_NAME" --source agent 2>/dev/null | awk 'NR>2 {print $4}' | cut -d'/' -f1 | head -n1 | grep -q .; then
    virsh --connect "$CONN" domifaddr "$VM_NAME" --source agent | awk 'NR>2 {print $4}' | cut -d'/' -f1 | head -n1
    return 0
  fi
  # Fallback via DHCP leases on the default network
  local mac; mac=$(virsh --connect "$CONN" domiflist "$VM_NAME" | awk 'NR>2 && $0!~/^$/ {print $5; exit}')
  if [ -n "$mac" ]; then
    virsh --connect "$CONN" net-dhcp-leases default | awk -v m="$mac" '$0 ~ m {print $5}' | cut -d'/' -f1 | head -n1
    return 0
  fi
  return 1
}

cmd_rdp() {
  local ip
  ip=$(vm_ip || true)
  [ -n "$ip" ] || die "Could not determine VM IP; ensure qemu-guest-agent or DHCP lease is available."
  echo "Connecting to $ip via FreeRDP"
  exec wlfreerdp /u:"''${RDP_USER:-Administrator}" /p:"''${RDP_PASS:-}" /v:"$ip" /dynamic-resolution +clipboard /gfx-h264:avc444 +gfx-progressive /rfx
}

cmd_rdp_app() {
  local app="''${1:-}"
  [ -n "$app" ] || die "Usage: winintegration rdp-app "'"APP_ALIAS_OR_PATH"'""
  local ip; ip=$(vm_ip || true)
  [ -n "$ip" ] || die "Could not determine VM IP; ensure RDP is enabled in guest."
  echo "Launching RemoteApp '$app' on $ip"
  exec wlfreerdp \
    /u:"''${RDP_USER:-Administrator}" /p:"''${RDP_PASS:-}" /v:"$ip" \
    /app:"''${app}" +clipboard /gfx-h264:avc444 +gfx-progressive /rfx /dynamic-resolution
}

cmd_rdp_explorer() {
  # Common helper to open Windows Explorer as RemoteApp
  cmd_rdp_app "||Explorer"
}

cmd_download_iso() {
  local url path
  url=$(resolve_win_iso_url)
  path="''${1:-$WIN_ISO_PATH_DEFAULT}"
  mkdir -p "$(dirname "$path")"
  echo "==> Downloading Windows ISO from: $url"
  need_cmd curl
  if curl -L --fail --progress-bar "$url" -o "$path.part"; then
    mv -f "$path.part" "$path"
    echo "$path" > "$CONF_DIR/win-iso.path"
    echo "$url" > "$CONF_DIR/win-iso.url"
    echo "Saved ISO to: $path"
  else
    rm -f "$path.part"
    die "Failed to download ISO"
  fi
}

cmd_attach_iso() {
  # Attach current ISO to running domain
  local iso; iso=$(resolve_win_iso_path || true)
  [ -n "$iso" ] && [ -f "$iso" ] || die "No ISO path configured. Use 'winintegration download-iso' or set WIN_ISO_FILE."
  echo "==> Attaching ISO $iso"
  virsh --connect "$CONN" change-media "$VM_NAME" sdb --insert --source "$iso" --update || die "change-media failed"
}

cmd_eject_iso() {
  echo "==> Ejecting install ISO (sdb)"
  virsh --connect "$CONN" change-media "$VM_NAME" sdb --eject --config || true
}

cmd_status() {
  virsh --connect "$CONN" dominfo "$VM_NAME" || true
}

usage() {
  cat <<USAGE
winintegration - orchestrate a high-performance Windows VM (libvirt/qemu)

Commands:
  init              Prepare data dirs and disk (from payload if present)
  define            Generate and define libvirt domain with tuned defaults
  define-install    Define domain preferring CDROM boot for installation
  start             Start the VM via libvirt
  autostart-on      Enable libvirt autostart for the VM
  autostart-off     Disable libvirt autostart for the VM
  viewer            Open SPICE viewer (virt-viewer)
  rdp               Full desktop via FreeRDP (requires RDP in guest)
  rdp-app APP       Launch a RemoteApp (e.g. '||Explorer' or exe path)
  rdp-explorer      Launch Windows Explorer as RemoteApp
  download-iso [P]  Download Windows ISO to path P (default: $WIN_ISO_PATH_DEFAULT)
  attach-iso        Attach configured ISO to the VM (drive sdb)
  eject-iso         Eject ISO from the VM (drive sdb)
  status            Show VM status via virsh

Environment:
  LIBVIRT_DEFAULT_URI   Defaults to qemu:///session for user session
  RDP_USER, RDP_PASS    Used by 'rdp' command
  WIN_ISO_URL           Overrides Windows ISO URL (default internal)
  WIN_ISO_FILE          Overrides Windows ISO path used by define/attach
  WIN_HOST_SHARE_DIR    Host dir to share via virtiofs (default: $HOME/Share/win)

Notes:
  - For best integration: install virtio drivers, Spice Guest Tools and
    QEMU Guest Agent from the attached virtio-win ISO inside Windows.
  - To install: run 'winintegration download-iso', then 'define-install' and
    'start'. After install completes, run 'eject-iso' and optionally 'define'
    again to switch boot back to disk.
  - Per-window integration in Hyprland is via RDP RemoteApp. Enable RDP in
    Windows (including NLA), then use 'rdp-app' to launch specific apps.
USAGE
}

main() {
  local cmd="''${1:-}"
  case "$cmd" in
    init) shift; cmd_init "$@" ;;
    define) shift; cmd_define "$@" ;;
    start) shift; cmd_start "$@" ;;
    autostart-on) shift; cmd_autostart_on "$@" ;;
    autostart-off) shift; cmd_autostart_off "$@" ;;
    viewer) shift; cmd_viewer "$@" ;;
    rdp) shift; cmd_rdp "$@" ;;
    rdp-app) shift; cmd_rdp_app "$@" ;;
    rdp-explorer) shift; cmd_rdp_explorer "$@" ;;
    download-iso) shift; cmd_download_iso "$@" ;;
    attach-iso) shift; cmd_attach_iso "$@" ;;
    eject-iso) shift; cmd_eject_iso "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown command: $cmd"; usage; exit 2 ;;
  esac
}

main "$@"
EOF
    chmod +x $out/bin/winintegration

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/winintegration" \
      --prefix PATH : ${lib.makeBinPath [ libvirt qemu virt-install unzip coreutils util-linux findutils freerdp3 virt-viewer curl ]} \
      --set EDK2_OVMF "${edk2-ovmf}" \
      --set VIRTIO_WIN "${virtio-win}" \
      --set WININTEGRATION_PAYLOAD_DIR "$out/share/winintegration/payload"
  '';

  meta = with lib; {
    description = "High-performance Windows VM integration (libvirt/KVM) with RDP/Spice helpers";
    homepage = "https://example.com/winintegration";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "winintegration";
  };
}
