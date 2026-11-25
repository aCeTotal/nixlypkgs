package signing

import (
	"encoding/pem"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// system fakes a NixOS toplevel.
func system(t *testing.T, cert []byte, modules map[string]string) string {
	t.Helper()
	pkg := func(name string) string {
		dir, err := os.MkdirTemp(storeDir, "*-"+name)
		if err != nil {
			t.Fatal(err)
		}
		return dir
	}
	write := func(path string, data []byte) {
		if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	link := func(target, path string) {
		if err := os.Symlink(target, path); err != nil {
			t.Fatal(err)
		}
	}
	kernel, boot, tree, toplevel := pkg("linux"), pkg("systemd"), pkg("linux-modules"), pkg("nixos-system")
	write(filepath.Join(kernel, "bzImage"), []byte("bzImage"))
	write(filepath.Join(boot, "systemd-bootx64.efi"), []byte("boot"))
	for name, content := range modules {
		write(filepath.Join(tree, "lib", "modules", "7.3.6", name), []byte(content))
	}
	link(filepath.Join(kernel, "bzImage"), filepath.Join(toplevel, "kernel"))
	link(filepath.Join(boot, "systemd-bootx64.efi"), filepath.Join(toplevel, "systemd-boot.efi"))
	link(tree, filepath.Join(toplevel, "kernel-modules"))
	write(filepath.Join(toplevel, "nixlyos-ca.pem"), cert)
	return toplevel
}

func TestCollectGroupsByPackage(t *testing.T) {
	storeDir = t.TempDir()
	one := system(t, nil, map[string]string{"kernel/a.ko": "a", "kernel/b.ko": "b", "modules.dep": "x"})
	files, err := Collect([]string{one, one})
	if err != nil {
		t.Fatal(err)
	}
	packages := map[Kind]map[string]int{Module: {}, EFI: {}}
	for _, file := range files {
		packages[file.Kind][file.Package]++
	}
	if len(files) != 4 || len(packages[Module]) != 1 || len(packages[EFI]) != 2 {
		t.Errorf("files %+v grouped as %v, want 2 modules in one package and 2 EFI files in two", files, packages)
	}
	for pkg := range packages[Module] {
		if !strings.HasSuffix(pkg, "-linux-modules") || strings.Contains(pkg, "/") {
			t.Errorf("module package = %q, want the store path name", pkg)
		}
	}
}

func TestTrustsNeedsTheActiveCA(t *testing.T) {
	storeDir = t.TempDir()
	cert := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: []byte("der")})
	trusted := system(t, cert, nil)
	if err := Trusts(CA{Fingerprint: "5050d80d22ecd471ea55df7034042c1e041341ff4066e7f6ff38e20b720df8ea"}, []string{trusted}); err != nil {
		t.Errorf("Trusts = %v, want the embedded CA trusted", err)
	}
	foreign := CA{Fingerprint: "0000000000000000000000000000000000000000000000000000000000000000"}
	if err := Trusts(foreign, []string{trusted}); !errors.Is(err, ErrUntrusted) {
		t.Errorf("Trusts = %v, want ErrUntrusted for a foreign CA", err)
	}
	if err := Trusts(foreign, []string{system(t, nil, nil)}); !errors.Is(err, ErrUntrusted) {
		t.Errorf("Trusts = %v, want ErrUntrusted without an embedded CA", err)
	}
}
