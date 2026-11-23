package profiles

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestKeepOnlyKeepsBothBranches(t *testing.T) {
	dir := t.TempDir()
	stableKey, testingKey, oldKey, nextKey := releaseKey("a", "1"), releaseKey("b", "2"), releaseKey("c", "3"), releaseKey("d", "4")
	for _, name := range []string{stableKey, testingKey, oldKey, nextKey} {
		if err := os.Mkdir(filepath.Join(dir, name), 0o750); err != nil {
			t.Fatal(err)
		}
	}
	if err := keepOnly(dir, []string{testingKey, stableKey, nextKey}); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var left []string
	for _, entry := range entries {
		left = append(left, entry.Name())
	}
	if want := []string{stableKey, testingKey, nextKey}; !slices.Equal(left, want) {
		t.Errorf("kept %v, want %v", left, want)
	}
}
