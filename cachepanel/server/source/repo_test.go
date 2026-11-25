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

func TestClonesReadOnly(t *testing.T) {
	r := seeded(t)
	server := httptest.NewServer(r.Handler())
	defer server.Close()
	url := server.URL + "/source.git"
	head := run(t, r.Dir(), "rev-parse", "main")
	for _, version := range []string{"0", "2"} {
		work := t.TempDir()
		run(t, work, "-c", "protocol.version="+version, "clone", "--quiet", url, ".")
		if got := run(t, work, "rev-parse", "HEAD"); got != head {
			t.Fatalf("v%s clone at %s, want %s", version, got, head)
		}
		run(t, work, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "--allow-empty", "-m", "Try")
		if out, err := exec.CommandContext(t.Context(), "git", "-C", work, "push", "--quiet", "origin", "HEAD:main").CombinedOutput(); err == nil {
			t.Fatalf("v%s push accepted: %s", version, out)
		}
	}
	shallow := t.TempDir()
	run(t, shallow, "init", "--quiet")
	run(t, shallow, "fetch", "--quiet", "--depth=1", url, head)
}

func TestPushNeedsMessages(t *testing.T) {
	r := seeded(t)
	work := t.TempDir()
	run(t, work, "clone", "--quiet", r.Dir(), ".")
	run(t, work, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "--allow-empty", "--allow-empty-message", "-m", "")
	if out, err := exec.CommandContext(t.Context(), "git", "-C", work, "push", "--quiet", "origin", "HEAD:main").CombinedOutput(); err == nil {
		t.Fatalf("blank message pushed: %s", out)
	}
	run(t, work, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "--amend", "--allow-empty", "-m", "Say why")
	run(t, work, "push", "--quiet", "origin", "HEAD:main")
}
