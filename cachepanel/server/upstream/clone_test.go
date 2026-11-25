package upstream

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func run(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.CommandContext(t.Context(), "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t",
		"GIT_COMMITTER_DATE=2026-11-24T23:30:00+00:00", "GIT_AUTHOR_DATE=2026-11-24T23:30:00+00:00")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func remote(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	run(t, dir, "init", "--quiet", "--initial-branch=main")
	for _, subject := range []string{"first", "second"} {
		run(t, dir, "commit", "--quiet", "--allow-empty", "-m", subject)
	}
	return dir
}

func TestBranchFollowsEveryCommit(t *testing.T) {
	upstream := remote(t)
	repo := cloneOf(t.TempDir(), "file://"+upstream)
	if err := repo.fetch(t.Context()); err != nil {
		t.Fatal(err)
	}
	first := run(t, upstream, "rev-parse", "HEAD~1")
	latest, err := repo.latest(t.Context(), Source{Branch: "main"})
	if err != nil || latest.Rev != run(t, upstream, "rev-parse", "HEAD") || latest.Version != "2026.11.24" {
		t.Fatalf("latest = %+v, %v", latest, err)
	}
	run(t, upstream, "commit", "--quiet", "--allow-empty", "-m", "third")
	if err := repo.fetch(t.Context()); err != nil {
		t.Fatal(err)
	}
	latest, _ = repo.latest(t.Context(), Source{Branch: "main"})
	log, err := repo.log(t.Context(), first, latest.Rev)
	if err != nil || len(log) != 2 || !strings.HasSuffix(log[0], " third") || !strings.HasSuffix(log[1], " second") {
		t.Fatalf("log = %q, %v", log, err)
	}
	if _, err := os.Stat(filepath.Join(repo.dir, "HEAD")); err != nil {
		t.Fatal("no clone kept")
	}
}

func TestTagsFollowTheNewestNumber(t *testing.T) {
	upstream := remote(t)
	run(t, upstream, "tag", "v1.9.0", "HEAD~1")
	run(t, upstream, "tag", "-a", "-m", "release", "v1.10.0")
	run(t, upstream, "tag", "v2.0-rc1")
	run(t, upstream, "tag", "nightly")
	repo := cloneOf(t.TempDir(), "file://"+upstream)
	if err := repo.fetch(t.Context()); err != nil {
		t.Fatal(err)
	}
	prefix := "v"
	latest, err := repo.latest(t.Context(), Source{Tags: &prefix})
	if err != nil || latest.Version != "1.10.0" || latest.Rev != run(t, upstream, "rev-parse", "HEAD") {
		t.Fatalf("latest = %+v, %v", latest, err)
	}
	none := "release-"
	if _, err := repo.latest(t.Context(), Source{Tags: &none}); err == nil {
		t.Fatal("found a tag that is not there")
	}
}

func TestNewerComparesNumbers(t *testing.T) {
	ordered := []string{"0.9", "0.10", "1.0", "1.0.1", "10.0"}
	for i := 1; i < len(ordered); i++ {
		if !newer(ordered[i], ordered[i-1]) || newer(ordered[i-1], ordered[i]) {
			t.Errorf("%s vs %s", ordered[i], ordered[i-1])
		}
	}
	if !slices.IsSortedFunc(ordered, func(a, b string) int {
		if newer(a, b) {
			return 1
		}
		return -1
	}) {
		t.Error("not sorted")
	}
}
