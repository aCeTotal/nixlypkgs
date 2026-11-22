package profiles

import (
	"strings"
	"testing"
)

var spec = Spec{
	Name:     "desktop",
	Platform: "desktop",
	Catalog:  []string{"mode", "brave"},
	Packages: []string{"blender", "python3Packages.numpy"},
	Modules:  []Module{{Slug: "motd", Source: "{ ... }: { }"}},
}

func TestDefaultNix(t *testing.T) {
	nix := defaultNix(spec)
	for _, want := range []string{
		`./modules/motd.nix`,
		`nixlyos.mode = lib.mkForce "desktop";`,
		`[ "blender" ]`,
		`[ "python3Packages" "numpy" ]`,
	} {
		if !strings.Contains(nix, want) {
			t.Errorf("default.nix lacks %q:\n%s", want, nix)
		}
	}
}

func TestProfileJSONListsModules(t *testing.T) {
	files, err := Files(spec, nil)
	if err != nil {
		t.Fatal(err)
	}
	if files[2].Path != "profile.json" || !strings.Contains(files[2].Content, `"brave"`) {
		t.Fatalf("profile.json: %+v", files[2])
	}
}

func TestArchiveIsReproducible(t *testing.T) {
	files, err := Files(spec, map[string]string{"nixlytile": "/nix/store/x-nixlytile"})
	if err != nil {
		t.Fatal(err)
	}
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
	files, err := Files(spec, nil)
	if err != nil {
		t.Fatal(err)
	}
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
