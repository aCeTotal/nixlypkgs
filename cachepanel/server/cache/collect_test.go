package cache

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const (
	app  = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-app"
	lib  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-lib"
	gone = "cccccccccccccccccccccccccccccccc-gone"
)

func write(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func publish(t *testing.T, dir, path string, references ...string) {
	t.Helper()
	write(t, dir, path[:hashLength]+narinfoSuffix,
		"StorePath: /nix/store/"+path+"\nURL: nar/"+path[:hashLength]+".nar\nReferences: "+strings.Join(references, " ")+"\n")
	write(t, dir, "nar/"+path[:hashLength]+".nar", "nar")
}

func TestSweepKeepsClosures(t *testing.T) {
	cache, err := Open(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	publish(t, cache.dir, app, app, lib)
	publish(t, cache.dir, lib)
	publish(t, cache.dir, gone)
	removed, err := cache.sweep([]string{"/nix/store/" + app})
	if err != nil {
		t.Fatal(err)
	}
	if removed != 2 {
		t.Errorf("removed %d files, want 2", removed)
	}
	var left []string
	for _, dir := range []string{".", "nar"} {
		entries, err := os.ReadDir(filepath.Join(cache.dir, dir))
		if err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			left = append(left, filepath.Join(dir, entry.Name()))
		}
	}
	slices.Sort(left)
	want := []string{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.narinfo", "nar",
		"nar/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.nar", "nar/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.nar", "nix-cache-info"}
	if !slices.Equal(left, want) {
		t.Errorf("left %v, want %v", left, want)
	}
}
