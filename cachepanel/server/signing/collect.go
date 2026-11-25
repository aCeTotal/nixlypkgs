package signing

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
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
		rel, err := inStore(real)
		if err != nil {
			return err
		}
		hash, err := hashFile(rel)
		files = append(files, File{Path: real, Hash: hash, Kind: kind, Package: strings.SplitN(rel, "/", 2)[0]})
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

// inStore is a path relative to the store.
func inStore(path string) (string, error) {
	rel, err := filepath.Rel(storeDir, path)
	if err != nil || !fs.ValidPath(rel) {
		return "", fmt.Errorf("%s is outside %s", path, storeDir)
	}
	return rel, nil
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

// hashFile digests a file in the store.
func hashFile(rel string) (_ string, err error) {
	file, err := os.DirFS(storeDir).Open(rel)
	if err != nil {
		return "", err
	}
	defer func() { err = errors.Join(err, file.Close()) }()
	sum := sha256.New()
	if _, err := io.Copy(sum, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(sum.Sum(nil)), nil
}
