package wizard

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"cachepanel/repo"
)

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.CommandContext(t.Context(), "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func TestPublish(t *testing.T) {
	work, remote := t.TempDir(), t.TempDir()
	git(t, work, "init", "--quiet", "--initial-branch=main")
	if err := os.MkdirAll(filepath.Join(work, "pkgs"), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(work, recipesList), []byte("[\n  \"zeta\"\n]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	git(t, work, "add", "-A")
	git(t, work, "commit", "--quiet", "-m", "start")
	git(t, remote, "clone", "--quiet", "--bare", work, ".")
	mirror, err := repo.Open(t.Context(), t.TempDir(), remote, "main")
	if err != nil {
		t.Fatal(err)
	}
	publisher := &Publisher{Mirror: mirror, Remote: remote, Key: "unused", Branch: "main", KnownHosts: filepath.Join(t.TempDir(), "known_hosts")}
	files := map[string][]byte{"default.nix": []byte("{ }\n"), "PKGBUILD": []byte("pkgname=demo\n")}
	sha, err := publisher.Publish(t.Context(), "demo", "1.0", files)
	if err != nil {
		t.Fatal(err)
	}
	if head := git(t, remote, "rev-parse", "main"); head != sha {
		t.Fatalf("remote main = %s, published %s", head, sha)
	}
	if list := git(t, remote, "show", "main:"+recipesList); !strings.Contains(list, "\"demo\"\n  \"zeta\"") {
		t.Fatalf("recipes.nix = %q", list)
	}
	if got := git(t, remote, "show", "main:pkgs/demo/PKGBUILD"); got != "pkgname=demo" {
		t.Fatalf("PKGBUILD = %q", got)
	}
	if subject := git(t, remote, "log", "-1", "--format=%s", "main"); subject != "demo: 1.0" {
		t.Fatalf("subject = %q", subject)
	}
}

func TestPublicKey(t *testing.T) {
	key := filepath.Join(t.TempDir(), "id")
	cmd := exec.CommandContext(t.Context(), "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("ssh-keygen: %v %s", err, out)
	}
	publisher := &Publisher{Remote: "git@github.com:a/b.git", Key: key}
	got, err := publisher.PublicKey(t.Context())
	if err != nil || !strings.HasPrefix(got, "ssh-ed25519 ") {
		t.Fatalf("PublicKey = %q, %v", got, err)
	}
	if _, err := (&Publisher{}).PublicKey(t.Context()); !errors.Is(err, errNoRemote) {
		t.Fatalf("unconfigured: %v", err)
	}
}
