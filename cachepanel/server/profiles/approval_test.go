package profiles

import (
	"slices"
	"testing"
)

func archive(t *testing.T, files ...File) []byte {
	t.Helper()
	_, packed, err := Archive(files)
	if err != nil {
		t.Fatal(err)
	}
	return packed
}

func TestChanges(t *testing.T) {
	before := archive(t, File{Path: "default.nix", Content: "a"}, File{Path: "modules/apps.nix", Content: "b"})
	after := archive(t, File{Path: "default.nix", Content: "a"}, File{Path: "modules/htpc.nix", Content: "c"})
	got, err := changes(before, after)
	if err != nil {
		t.Fatal(err)
	}
	want := []changedFile{{Path: "modules/apps.nix", Change: fileRemoved}, {Path: "modules/htpc.nix", Change: fileAdded}}
	if !slices.Equal(got, want) {
		t.Errorf("changes = %v, want %v", got, want)
	}
}

func TestFirstReleaseAddsEverything(t *testing.T) {
	got, err := changes(nil, archive(t, File{Path: "default.nix", Content: "a"}))
	if err != nil {
		t.Fatal(err)
	}
	if want := []changedFile{{Path: "default.nix", Change: fileAdded}}; !slices.Equal(got, want) {
		t.Errorf("changes = %v, want %v", got, want)
	}
}

func TestEditedFileIsChanged(t *testing.T) {
	got, err := changes(archive(t, File{Path: "modules/apps.nix", Content: "a"}), archive(t, File{Path: "modules/apps.nix", Content: "b"}))
	if err != nil {
		t.Fatal(err)
	}
	if want := []changedFile{{Path: "modules/apps.nix", Change: fileChanged}}; !slices.Equal(got, want) {
		t.Errorf("changes = %v, want %v", got, want)
	}
}

func TestPinsAndSignaturesAreNotBase(t *testing.T) {
	got, err := changes(archive(t, File{Path: "pins.nix", Content: "{ }"}),
		archive(t, File{Path: "pins.nix", Content: "{ x = 1; }"}, File{Path: "signing.nix", Content: "{ }"}))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("changes = %v, want none", got)
	}
}
