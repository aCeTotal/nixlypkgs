package update

import "testing"

func TestStorePath(t *testing.T) {
	cases := map[string]string{
		"/nix/store/abc-cachepanel-0.1.0/bin/.cachepanel-wrapped": "/nix/store/abc-cachepanel-0.1.0",
		"/nix/store/abc-cachepanel-0.1.0":                         "/nix/store/abc-cachepanel-0.1.0",
		"/home/dev/cachepanel":                                    "/home/dev/cachepanel",
	}
	for path, want := range cases {
		if got := storePath(path); got != want {
			t.Errorf("storePath(%q) = %q, want %q", path, got, want)
		}
	}
}
