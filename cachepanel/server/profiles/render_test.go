package profiles

import (
	"strings"
	"testing"
)

var spec = Spec{
	Name:     "desktop",
	Platform: "desktop",
	Kernel:   "enterprise",
	Packages: []string{"blender", "python3Packages.numpy"},
	Modules:  []Module{{Slug: "system", Source: "{ ... }: { }"}, {Slug: "motd", Source: "{ ... }: { }"}},
}

func TestDefaultNix(t *testing.T) {
	nix := defaultNix(spec)
	for _, want := range []string{
		"./modules/system.nix\n    ./modules/motd.nix",
		`nixlyos.mode = lib.mkForce "desktop";`,
		`nixlyos.kernel = lib.mkForce "enterprise";`,
		`[ "blender" ]`,
		`[ "python3Packages" "numpy" ]`,
	} {
		if !strings.Contains(nix, want) {
			t.Errorf("default.nix lacks %q:\n%s", want, nix)
		}
	}
}

func TestFilesCarryModules(t *testing.T) {
	files := Files(spec, nil)
	if len(files) != 4 || files[2].Path != "modules/system.nix" || files[3].Path != "modules/motd.nix" {
		t.Fatalf("files: %+v", files)
	}
}

func TestArchiveIsReproducible(t *testing.T) {
	files := Files(spec, map[string]Pin{"nixlytile": {Version: 1, Out: "/nix/store/x-nixlytile"}})
	first, _, err := Archive(files)
	if err != nil {
		t.Fatal(err)
	}
	second, _, err := Archive(files)
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatalf("hashes differ: %s %s", first, second)
	}
	changed := append([]File{}, files...)
	changed[0].Content += " "
	third, _, err := Archive(changed)
	if err != nil {
		t.Fatal(err)
	}
	if third == first {
		t.Fatal("content change kept the hash")
	}
}

func TestArchiveRoundTrips(t *testing.T) {
	files := Files(spec, nil)
	_, archive, err := Archive(files)
	if err != nil {
		t.Fatal(err)
	}
	read, err := readArchive(archive)
	if err != nil {
		t.Fatal(err)
	}
	if len(read) != len(files) || read[0] != files[0] {
		t.Fatalf("round trip lost files: %+v", read)
	}
}
