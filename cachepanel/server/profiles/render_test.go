package profiles

import (
	"slices"
	"strings"
	"testing"
)

var spec = Spec{
	Name:           "desktop",
	Platform:       "desktop",
	Kernel:         "enterprise",
	KernelSettings: map[string]string{"tickRate": "300", "hugepages": "madvise"},
	Packages:       []string{"blender", "python3Packages.numpy"},
	Modules:        []string{"motd", "gaming"},
}

func TestDefaultNix(t *testing.T) {
	nix := defaultNix(spec)
	for _, want := range []string{
		`nixlyos.mode = lib.mkForce "desktop";`,
		`nixlyos.kernel = lib.mkForce "enterprise";`,
		`nixlyos.kernelSettings = lib.mkForce { "hugepages" = "madvise"; "tickRate" = "300"; };`,
		`[ "blender" ]`,
		`[ "python3Packages" "numpy" ]`,
	} {
		if !strings.Contains(nix, want) {
			t.Errorf("default.nix lacks %q:\n%s", want, nix)
		}
	}
}

func TestFilesListChosenModules(t *testing.T) {
	files := Files(spec, nil)
	if len(files) != 3 || files[1].Path != modulesFile || files[1].Content != "[\n  \"gaming\"\n  \"motd\"\n]\n" {
		t.Fatalf("files: %+v", files)
	}
	if strings.Contains(files[0].Content, "imports") {
		t.Fatalf("default.nix imports modules itself:\n%s", files[0].Content)
	}
}

func TestArchiveFoldersFollowFiles(t *testing.T) {
	flat := folders([]File{{Path: "default.nix"}, {Path: "pins.nix"}})
	nested := folders([]File{{Path: "default.nix"}, {Path: "modules/a.nix"}, {Path: "modules/b.nix"}})
	if !slices.Equal(flat, []string{treeRoot}) || !slices.Equal(nested, []string{treeRoot, treeRoot + "modules/"}) {
		t.Fatalf("flat %v, nested %v", flat, nested)
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
