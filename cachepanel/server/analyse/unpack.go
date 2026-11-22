package analyse

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"cachepanel/nixexpr"
)

const unpackTimeout = 20 * time.Minute

// Nix rejects setuid and shared-writable outputs.
const normalize = " && chmod -R u+w,go-w,ug-s $out"

var unpackScripts = map[Kind]string{
	ArchiveFile: "mkdir $out && bsdtar -xf $src -C $out" + normalize,
	DebPackage:  "dpkg-deb -x $src $out && dpkg-deb -e $src $out/DEBIAN" + normalize,
	RpmPackage:  "mkdir $out && bsdtar -xf $src -C $out" + normalize,
}

// Unpack extracts in the sandbox.
func Unpack(ctx context.Context, flakeRef, file string, kind Kind) (string, error) {
	pkgs := nixexpr.Pkgs(flakeRef)
	src := "builtins.storePath " + nixexpr.String(file)
	expr := pkgs + `.appimageTools.extractType2 { pname = "appimage"; version = "0"; src = ` + src + `; }`
	if script, ok := unpackScripts[kind]; ok {
		expr = pkgs + `.runCommand "unpacked" { src = ` + src + `; nativeBuildInputs = with ` + pkgs +
			`; [ libarchive dpkg ]; } ` + nixexpr.String(script)
	}
	ctx, cancel := context.WithTimeout(ctx, unpackTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "build", "--impure", "--no-link", "--print-out-paths", "--expr", expr)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("pakk ut: %w\n%s", err, stderr.String())
	}
	return strings.TrimSpace(string(out)), nil
}
