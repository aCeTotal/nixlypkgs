package profiles

import (
	"errors"
	"slices"
	"testing"
)

func TestProfileRoundTrip(t *testing.T) {
	text, err := Profile{Title: "Desktop", Platform: "desktop", Kernel: "performance",
		Modules: []string{"gaming", "audio", "gaming"}, Packages: []string{"blender", "gimp", "blender"}}.encode()
	if err != nil {
		t.Fatal(err)
	}
	profile, err := decodeProfile("desktop", text)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(profile.Modules, []string{"audio", "gaming"}) || !slices.Equal(profile.Packages, []string{"blender", "gimp"}) {
		t.Fatalf("profile = %+v", profile)
	}
	if profile.KernelSettings == nil || profile.PinnedSha != nil {
		t.Fatalf("defaults = %+v", profile)
	}
	if again, _ := profile.encode(); again != text {
		t.Fatalf("not stable:\n%s\n%s", text, again)
	}
}

func TestDecodeRefusesBadProfiles(t *testing.T) {
	cases := map[string]error{
		`{"title": "X", "platform": "toaster"}`:                      errPlatform,
		`{"title": "", "platform": "desktop"}`:                       errTitle,
		`{"title": "X", "platform": "desktop", "packages": ["a b"]}`: errPackage,
	}
	for text, want := range cases {
		if _, err := decodeProfile("desktop", text); !errors.Is(err, want) {
			t.Errorf("%s: %v, want %v", text, err, want)
		}
	}
	if _, err := decodeProfile("Bad_Name", `{"title": "X", "platform": "desktop"}`); !errors.Is(err, errName) {
		t.Errorf("bad name: %v", err)
	}
}
