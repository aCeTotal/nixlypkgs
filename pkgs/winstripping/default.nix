{ lib
, stdenvNoCC
, makeWrapper
, wimlib
, cpio
, cabextract
, cdrkit
, xorriso
, p7zip
, coreutils
, findutils
, gawk
}:

stdenvNoCC.mkDerivation rec {
  pname = "winstripping";
  version = "0.1.0";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cat > $out/bin/winstripping <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Tools expected in PATH (provided by wrapper):
#  - wimlib-imagex (from wimlib)
#  - 7z (from p7zip)
#  - cabextract, cpio, xorriso, genisoimage, isoinfo

die() { echo "error: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

volid_from_iso() {
  local iso="$1"
  if command -v xorriso >/dev/null 2>&1; then
    xorriso -indev "$iso" -pvd_info 2>/dev/null | awk -F': ' '/Volume id/ {print $2; exit}'
    return 0
  fi
  if command -v isoinfo >/dev/null 2>&1; then
    isoinfo -d -i "$iso" 2>/dev/null | awk -F': ' '/Volume id/ {print $2; exit}'
    return 0
  fi
  return 1
}

cmd_extract() {
  local iso="$1" workdir="$2"
  [ -f "$iso" ] || die "ISO not found: $iso"
  mkdir -p "$workdir/extracted"
  echo "==> Extracting ISO to $workdir/extracted"
  7z x -y -o"$workdir/extracted" "$iso" >/dev/null
  local vid
  vid=$(volid_from_iso "$iso" || true)
  if [ -n "$vid" ]; then
    echo "$vid" > "$workdir/VOLUME_ID.txt"
    echo "Saved volume ID: $vid"
  else
    echo "warning: could not derive volume ID"
  fi
  echo "Done. You may now modify files under $workdir/extracted"
}

cmd_convert_esd() {
  local workdir="$1"
  local sources="$workdir/extracted/sources"
  [ -d "$sources" ] || die "Sources directory not found: $sources (run extract first)"

  local esd="$sources/install.esd"
  local wim="$sources/install.wim"
  [ -f "$esd" ] || die "install.esd not found in $sources"

  echo "==> Converting install.esd -> install.wim (LZX)"
  wimlib-imagex export "$esd" all "$wim" --compress=LZX >/dev/null
  echo "Removing original ESD"
  rm -f "$esd"
  echo "Done: $wim"
}

cmd_pack() {
  local workdir="$1" out_iso="$2"; shift 2
  local volid="${1:-}"
  local srcdir="$workdir/extracted"
  [ -d "$srcdir" ] || die "Extracted tree not found: $srcdir (run extract first)"

  if [ -z "$volid" ] && [ -f "$workdir/VOLUME_ID.txt" ]; then
    volid=$(cat "$workdir/VOLUME_ID.txt")
  fi
  if [ -z "$volid" ]; then
    volid="WIN11_CUSTOM"
  fi

  # Ensure boot loaders exist
  local bios_boot="$srcdir/boot/etfsboot.com"
  local efi_boot="$srcdir/efi/microsoft/boot/efisys.bin"
  local efi_boot_np="$srcdir/efi/microsoft/boot/efisys_noprompt.bin"
  [ -f "$bios_boot" ] || die "Missing BIOS boot image: boot/etfsboot.com"
  if [ -f "$efi_boot" ]; then
    :
  elif [ -f "$efi_boot_np" ]; then
    efi_boot="$efi_boot_np"
  else
    die "Missing UEFI boot image: efi/microsoft/boot/efisys(.noprompt).bin"
  fi

  echo "==> Building ISO: $out_iso (VOLID=$volid)"
  if command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs \
      -iso-level 3 \
      -o "$out_iso" \
      -full-iso9660-filenames \
      -volid "$volid" \
      -eltorito-boot boot/etfsboot.com \
        -no-emul-boot -boot-load-size 8 -boot-info-table \
      -eltorito-alt-boot \
        -e "${efi_boot#${srcdir}/}" -no-emul-boot \
      -isohybrid-gpt-basdat \
      -udf -J -joliet-long \
      "$srcdir"
  else
    need genisoimage
    genisoimage \
      -iso-level 3 \
      -o "$out_iso" \
      -V "$volid" \
      -b boot/etfsboot.com -no-emul-boot -boot-load-size 8 -boot-info-table \
      -eltorito-alt-boot -e "${efi_boot#${srcdir}/}" -no-emul-boot \
      -udf -J -joliet-long \
      "$srcdir"
  fi
  echo "Done: $out_iso"
}

usage() {
  cat <<USAGE
winstripping - helper for Windows ISO strip/repack

Commands:
  extract <win.iso> <workdir>      Extract ISO into <workdir>/extracted, save VOLID
  convert-esd <workdir>            Convert sources/install.esd -> install.wim (LZX)
  pack <workdir> <out.iso> [VOLID] Repack extracted tree into a bootable ISO

Notes:
  - After 'extract', manually remove/add files under <workdir>/extracted as needed.
  - 'convert-esd' is optional but recommended if you modified sources.
  - Repacking uses xorriso if available; falls back to genisoimage.
USAGE
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    extract) [ $# -ge 2 ] || { usage; exit 2; }; cmd_extract "$@" ;;
    convert-esd) [ $# -ge 1 ] || { usage; exit 2; }; cmd_convert_esd "$@" ;;
    pack) [ $# -ge 2 ] || { usage; exit 2; }; cmd_pack "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown command: $cmd"; usage; exit 2 ;;
  esac
}

main "$@"
EOF
    chmod +x "$out/bin/winstripping"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/winstripping" \
      --prefix PATH : ${lib.makeBinPath [ wimlib cpio cabextract cdrkit xorriso p7zip coreutils findutils gawk ]}
  '';

  meta = with lib; {
    description = "Toolkit and helper to extract/strip/repack Windows 11 ISO (wimlib, xorriso, genisoimage, 7z, cpio, cabextract)";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "winstripping";
  };
}

