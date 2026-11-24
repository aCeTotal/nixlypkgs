package profiles

import "testing"

func TestStableMatchesTestingWithSamePins(t *testing.T) {
	pins := map[string]Pin{"nixlytile": {Version: 7, Out: "/nix/store/x-nixlytile"}}
	tested := Files(spec, pins)
	signed := archive(t, append(tested, File{Path: signingFile, Content: "{ }"})...)
	files, err := readArchive(signed)
	if err != nil {
		t.Fatal(err)
	}
	stable, _, err := Archive(withPins(files, pins))
	if err != nil {
		t.Fatal(err)
	}
	source, err := sourceHash(signed)
	if err != nil {
		t.Fatal(err)
	}
	if stable != source {
		t.Errorf("stable %s, want testing's source %s", stable, source)
	}
	older, _, err := Archive(withPins(files, map[string]Pin{"nixlytile": {Version: 6, Out: "/nix/store/y-nixlytile"}}))
	if err != nil {
		t.Fatal(err)
	}
	if older == source {
		t.Error("an older pin must give another tree")
	}
}
