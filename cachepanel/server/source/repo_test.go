package source

import (
	"net/http/httptest"
	"os/exec"
	"strings"
	"testing"

	"cachepanel/config"
)

func run(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.CommandContext(t.Context(), "git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func TestOpenSeedsOnce(t *testing.T) {
	seed := t.TempDir()
	run(t, seed, "init", "--quiet", "--initial-branch=main")
	run(t, seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "--allow-empty", "-m", "start")
	cfg := config.Config{StateDir: t.TempDir(), SourceSeed: seed, Branch: "main", PublicURL: "https://panel.test"}
	for range 2 {
		if _, err := Open(t.Context(), cfg); err != nil {
			t.Fatal(err)
		}
	}
	r := At(cfg)
	if got, want := run(t, r.Dir(), "rev-parse", "main"), run(t, seed, "rev-parse", "main"); got != want {
		t.Fatalf("main = %s, seed %s", got, want)
	}
	if remotes := run(t, r.Dir(), "remote"); remotes != "" {
		t.Fatalf("remotes left: %q", remotes)
	}
	if got := run(t, r.Dir(), "config", "receive.denyNonFastForwards"); got != "true" {
		t.Fatalf("denyNonFastForwards = %q", got)
	}
	if got := r.Source("abc"); got != "git+https://panel.test/source.git?rev=abc" {
		t.Fatalf("Source = %q", got)
	}
}

func TestReadOnly(t *testing.T) {
	cases := map[string]bool{
		"GET /source.git/info/refs?service=git-upload-pack":    true,
		"POST /source.git/git-upload-pack":                     true,
		"GET /source.git/info/refs?service=git-receive-pack":   false,
		"POST /source.git/git-receive-pack":                    false,
		"GET /nixlypkgs.git/info/refs?service=git-upload-pack": false,
		"GET /source.git/HEAD":                                 false,
	}
	for request, want := range cases {
		method, target, _ := strings.Cut(request, " ")
		if got := readOnly(httptest.NewRequest(method, target, nil)); got != want {
			t.Errorf("%s = %v, want %v", request, got, want)
		}
	}
}
