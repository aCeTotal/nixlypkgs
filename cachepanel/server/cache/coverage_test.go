package cache

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCoverFindsEveryMissingPath(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("nix is not installed")
	}
	git, err := exec.LookPath("git")
	if err != nil {
		t.Skip("git is not installed")
	}
	resolved, err := filepath.EvalSymlinks(git)
	if err != nil || !strings.HasPrefix(resolved, "/nix/store/") {
		t.Skip("git is not in the Nix store")
	}
	root := strings.Join(strings.SplitN(resolved, "/", 5)[:4], "/")
	c, err := Open(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	coverage, err := c.Cover(t.Context(), root)
	if err != nil {
		t.Fatal(err)
	}
	if coverage.Paths == 0 || len(coverage.Missing) != coverage.Paths || coverage.Bytes == 0 {
		t.Fatalf("empty cache covers %+v", coverage)
	}
	for _, path := range coverage.Missing {
		name := filepath.Base(path)[:storeHashLength] + narinfoSuffix
		if err := os.WriteFile(filepath.Join(c.dir, name), nil, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if coverage, err = c.Cover(t.Context(), root); err != nil || len(coverage.Missing) != 0 {
		t.Fatalf("full cache covers %+v, %v", coverage, err)
	}
}
