package signing

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// storeDir roots every package; tests move it.
var storeDir = "/nix/store"

// Collect finds kernel, bootloader and modules.
func Collect(toplevels []string) ([]File, error) {
	seen := map[string]bool{}
	var files []File
	add := func(path string, kind Kind) error {
		real, err := filepath.EvalSymlinks(path)
		if err != nil || seen[real] {
			return err
		}
		seen[real] = true
		pkg, err := packageOf(real)
		if err != nil {
			return err
		}
		hash, err := hashFile(real)
		files = append(files, File{Path: real, Hash: hash, Kind: kind, Package: pkg})
		return err
	}
	for _, toplevel := range toplevels {
		for _, efi := range []string{"kernel", "systemd-boot.efi"} {
			if err := add(filepath.Join(toplevel, efi), EFI); err != nil {
				return nil, err
			}
		}
		err := walk(filepath.Join(toplevel, "kernel-modules", "lib", "modules"), func(path string) error {
			if !strings.HasSuffix(path, ".ko") {
				return nil
			}
			return add(path, Module)
		})
		if err != nil {
			return nil, err
		}
	}
	return files, nil
}

// packageOf names a file's store path.
func packageOf(path string) (string, error) {
	rel, err := filepath.Rel(storeDir, path)
	if err != nil || strings.HasPrefix(rel, "..") {
		return "", fmt.Errorf("%s is outside %s", path, storeDir)
	}
	return strings.SplitN(rel, string(filepath.Separator), 2)[0], nil
}

// walk follows the symlinked module tree.
func walk(dir string, visit func(string) error) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		path := filepath.Join(dir, entry.Name())
		info, err := os.Stat(path)
		if err != nil {
			return err
		}
		if info.IsDir() {
			err = walk(path, visit)
		} else {
			err = visit(path)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(sum.Sum(nil)), nil
}
