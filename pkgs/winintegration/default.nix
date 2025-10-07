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
, virt-viewer
}:

stdenvNoCC.mkDerivation rec {
  pname = "winintegration";
  version = "0.1.0";

  # Placeholder payload: replace URL + sha256 when known
  src = fetchzip {
    url = "https://example.com/path/to/windows-guest-payload.zip";
    # Replace with the real hash when the URL is known
    sha256 = lib.fakeSha256;
    stripRoot = false;
  };

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/winintegration $out/bin

    # Keep payload accessible at runtime; we do not assume its structure
    cp -a "$src" "$out/share/winintegration/payload"

    # Main orchestrator
    cat > $out/bin/winintegration <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

VM_NAME="winintegration"
CONN="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

XDG_DATA_HOME_DEFAULT="$HOME/.local/share"
XDG_STATE_HOME_DEFAULT="$HOME/.local/state"
XDG_CONFIG_HOME_DEFAULT="$HOME/.config"

DATA_DIR="${XDG_DATA_HOME:-$XDG_DATA_HOME_DEFAULT}/winintegration"
STATE_DIR="${XDG_STATE_HOME:-$XDG_STATE_HOME_DEFAULT}/winintegration"
CONF_DIR="${XDG_CONFIG_HOME:-$XDG_CONFIG_HOME_DEFAULT}/winintegration"

PAYLOAD_DIR="${WININTEGRATION_PAYLOAD_DIR:-}"

mkdir -p "$DATA_DIR" "$STATE_DIR" "$CONF_DIR"

die() { echo "error: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

find_ovmf() {
  # Resolve OVMF paths from EDK2_OVMF (provided by wrapper)
  local base="${EDK2_OVMF:-}"
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
  local base="${VIRTIO_WIN:-}"
  [ -n "$base" ] || return 0
  local iso
  iso=$(find "$base" -type f -name '*.iso' | head -n1 || true)
  [ -n "$iso" ] || return 0
  echo "$iso"
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
  # Heuristics: reserve 2 CPUs and 2 GiB for host
  [ "$cpus" -gt 2 ] && cpus=$((cpus-2)) || cpus=2
  guest_mem=$(( total_mem - 2048 ))
  [ "$guest_mem" -lt 4096 ] && guest_mem=4096
  iothreads=1

  local ovmf ovmf_code ovmf_vars vars_copy
  ovmf=$(find_ovmf)
  ovmf_code="${ovmf%|*}"; ovmf_vars="${ovmf#*|}"
  vars_copy="$DATA_DIR/OVMF_VARS_${VM_NAME}.fd"
  if [ ! -f "$vars_copy" ]; then
    cp -f "$ovmf_vars" "$vars_copy"
  fi

  local disk; disk=$(ensure_disk)
  local virtio_iso; virtio_iso=$(find_virtio_win_iso || true)

  # virtiofs share for payload if present
  local fs_xml=""; local fs_target="winintegration"
  if [ -n "$PAYLOAD_DIR" ] && [ -d "$PAYLOAD_DIR" ]; then
    fs_xml="\n    <filesystem type='mount' accessmode='passthrough'>\n      <driver type='virtiofs'/>\n      <source dir='${PAYLOAD_DIR}'/>\n      <target dir='${fs_target}'/>\n    </filesystem>"
  fi

  local cdrom_virtio=""
  if [ -n "$virtio_iso" ]; then
    cdrom_virtio="\n    <disk type='file' device='cdrom'>\n      <driver name='qemu' type='raw'/>\n      <source file='${virtio_iso}'/>\n      <target dev='sdc' bus='sata'/>\n      <readonly/>\n    </disk>"
  fi

  cat > "$CONF_DIR/${VM_NAME}.xml" <<XML
<domain type='kvm'>
  <name>${VM_NAME}</name>
  <memory unit='MiB'>${guest_mem}</memory>
  <currentMemory unit='MiB'>${guest_mem}</currentMemory>
  <vcpu placement='static'>${cpus}</vcpu>
  <iothreads>${iothreads}</iothreads>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>${ovmf_code}</loader>
    <nvram>${vars_copy}</nvram>
    <boot dev='hd'/>
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
      <vendor_id state='on' value='KVMNvrdia'/>
      <frequencies state='on'/>
      <reenlightenment state='on'/>
    </hyperv>
  </features>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' dies='1' cores='${cpus}' threads='1'/>
  </cpu>
  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='hpet' present='no'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hypervclock' present='yes'/>
  </clock>
  <memoryBacking>
    <hugepages/>
  </memoryBacking>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none' io='native' discard='unmap'/>
      <source file='${disk}'/>
      <target dev='vda' bus='virtio'/>
    </disk>${cdrom_virtio}
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
    <graphics type='spice' autoport='yes' listen='127.0.0.1'>
      <image compression='off'/>
    </graphics>${fs_xml}
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
  virsh --connect "$CONN" define "$CONF_DIR/${VM_NAME}.xml" >/dev/null
  echo "Defined: $VM_NAME"
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
  exec wlfreerdp /u:"${RDP_USER:-Administrator}" /p:"${RDP_PASS:-}" /v:"$ip" /dynamic-resolution +clipboard /gfx-h264:avc444 +gfx-progressive /rfx
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
  start             Start the VM via libvirt
  autostart-on      Enable libvirt autostart for the VM
  autostart-off     Disable libvirt autostart for the VM
  viewer            Open SPICE viewer (virt-viewer)
  rdp               Connect via FreeRDP (requires RDP enabled in guest)
  status            Show VM status via virsh

Environment:
  LIBVIRT_DEFAULT_URI   Defaults to qemu:///session for user session
  RDP_USER, RDP_PASS    Used by 'rdp' command

Notes:
  - This package embeds a placeholder payload. Replace URL+hash in the
    derivation to include your guest files (e.g. QCOW2, scripts, drivers).
  - Per-app window integration is intended via RDP/RemoteApp in the guest.
    Ensure your Windows payload enables RDP and RemoteApp publishing.
USAGE
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    init) shift; cmd_init "$@" ;;
    define) shift; cmd_define "$@" ;;
    start) shift; cmd_start "$@" ;;
    autostart-on) shift; cmd_autostart_on "$@" ;;
    autostart-off) shift; cmd_autostart_off "$@" ;;
    viewer) shift; cmd_viewer "$@" ;;
    rdp) shift; cmd_rdp "$@" ;;
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
      --prefix PATH : ${lib.makeBinPath [ libvirt qemu virt-install unzip coreutils util-linux findutils freerdp3 virt-viewer ]} \
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
