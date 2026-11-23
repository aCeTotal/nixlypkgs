package pkgbuild

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"cachepanel/nixexpr"
)

const readTimeout = 3 * time.Minute

var errNoName = errors.New("the PKGBUILD lacks pkgname or pkgver")

// Sourced inside the build sandbox.
const emitScript = `set +eu +o pipefail
cd "$dir"
CARCH=x86_64 CHOST=x86_64-pc-linux-gnu srcdir=/build/src pkgdir=/build/pkg startdir=$dir
source ./PKGBUILD >/dev/null 2>&1
emit() {
  local key=$1 value
  shift
  for value in "$@"; do
    printf '%s = %s\n' "$key" "${value//$'\n'/ }"
  done
}
{
  emit pkgbase "${pkgbase:-${pkgname[0]}}"
  emit pkgname "${pkgname[@]}"
  emit pkgver "$pkgver"
  emit pkgrel "$pkgrel"
  emit epoch "$epoch"
  emit pkgdesc "$pkgdesc"
  emit url "$url"
  emit license "${license[@]}"
  emit depends "${depends[@]}" "${depends_x86_64[@]}"
  emit makedepends "${makedepends[@]}" "${makedepends_x86_64[@]}"
  emit source "${source[@]}" "${source_x86_64[@]}"
  emit noextract "${noextract[@]}"
  emit options "${options[@]}"
  emit function $(declare -F | cut -d" " -f3)
} >"$out"
`

// Read sources the PKGBUILD sandboxed.
func Read(ctx context.Context, flakeRef, dir string) (Info, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	expr := nixexpr.Pkgs(flakeRef) + `.runCommand "pkgbuild-info" { dir = builtins.path { path = ` +
		nixexpr.String(dir) + `; name = "pkgbuild"; }; } ` + nixexpr.String(emitScript)
	cmd := exec.CommandContext(ctx, "nix", "build", "--impure", "--no-link", "--print-out-paths", "--expr", expr)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return Info{}, fmt.Errorf("read PKGBUILD: %w\n%s", err, stderr.String())
	}
	text, err := os.ReadFile(strings.TrimSpace(string(out)))
	if err != nil {
		return Info{}, err
	}
	info := parseInfo(string(text))
	if len(info.Names) == 0 || info.Version == "" {
		return Info{}, errNoName
	}
	return info, nil
}
