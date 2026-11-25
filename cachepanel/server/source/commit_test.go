package source

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cachepanel/config"
)

var tester = Author{Name: "tester", Email: "tester@panel.test"}

// seeded opens a source holding a script and a module.
func seeded(t *testing.T) *Repo {
	t.Helper()
	seed := t.TempDir()
	run(t, seed, "init", "--quiet", "--initial-branch=main")
	if err := os.MkdirAll(filepath.Join(seed, "pkgs/demo"), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(seed, "pkgs/demo/default.nix"), []byte("{ }\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(seed, "run.sh"), []byte("echo one\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	run(t, seed, "add", "-A")
	run(t, seed, "update-index", "--chmod=+x", "run.sh")
	run(t, seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-m", "start")
	cfg := config.Config{StateDir: t.TempDir(), SourceSeed: seed, Branch: "main", PublicURL: "https://panel.test", Hooks: hooks(t)}
	r, err := Open(t.Context(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// hooks links the packaged pre-receive hook.
func hooks(t *testing.T) string {
	t.Helper()
	script, err := filepath.Abs("pre-receive.sh")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err := os.Symlink(script, filepath.Join(dir, "pre-receive")); err != nil {
		t.Fatal(err)
	}
	return dir
}

func text(value string) *string {
	return &value
}

func TestCommitEditsCreatesAndDeletes(t *testing.T) {
	r := seeded(t)
	base, _ := r.Head(t.Context())
	edit := Edit{Base: base, Message: "change things", Changes: []FileChange{
		{Path: "run.sh", Content: text("echo two\n")},
		{Path: "pkgs/new/default.nix", Content: text("{ new = true; }\n")},
		{Path: "pkgs/demo/default.nix"},
	}}
	sha, err := r.Commit(t.Context(), edit, tester)
	if err != nil {
		t.Fatal(err)
	}
	if head, _ := r.Head(t.Context()); head != sha {
		t.Fatalf("head %s, committed %s", head, sha)
	}
	if blob, err := r.File(t.Context(), "run.sh"); err != nil || blob.Text != "echo two\n" {
		t.Fatalf("run.sh = %+v, %v", blob, err)
	}
	if mode := run(t, r.Dir(), "ls-tree", sha, "run.sh"); !strings.HasPrefix(mode, "100755") {
		t.Fatalf("run.sh lost its mode: %s", mode)
	}
	if _, err := r.File(t.Context(), "pkgs/demo/default.nix"); err == nil {
		t.Fatal("deleted file still reads")
	}
	if author := run(t, r.Dir(), "log", "-1", "--format=%an <%ae>"); author != "tester <tester@panel.test>" {
		t.Fatalf("author = %q", author)
	}
	if _, err := r.Commit(t.Context(), edit, tester); !errors.Is(err, errMoved) {
		t.Fatalf("stale base: %v", err)
	}
	elsewhere := Edit{Base: base, Message: "elsewhere", Changes: []FileChange{{Path: "docs/notes.md", Content: text("hi\n")}}}
	if _, err := r.Commit(t.Context(), elsewhere, tester); err != nil {
		t.Fatalf("an unrelated move refused: %v", err)
	}
	same := Edit{Base: sha, Message: "again", Changes: []FileChange{{Path: "run.sh", Content: text("echo two\n")}}}
	if _, err := r.Commit(t.Context(), same, tester); !errors.Is(err, ErrUnchanged) {
		t.Fatalf("no-op: %v", err)
	}
	folder := Edit{Base: sha, Message: "clobber", Changes: []FileChange{{Path: "pkgs", Content: text("x")}}}
	if _, err := r.Commit(t.Context(), folder, tester); !errors.Is(err, errFolder) {
		t.Fatalf("folder: %v", err)
	}
}

func TestRevertAndHistory(t *testing.T) {
	r := seeded(t)
	base, _ := r.Head(t.Context())
	changed, err := r.Commit(t.Context(), Edit{Base: base, Message: "two", Changes: []FileChange{{Path: "run.sh", Content: text("echo two\n")}}}, tester)
	if err != nil {
		t.Fatal(err)
	}
	details, err := r.Show(t.Context(), changed)
	if err != nil || details.Parent != base || len(details.Files) != 1 || !strings.Contains(details.Files[0].Patch, "+echo two") {
		t.Fatalf("show = %+v, %v", details, err)
	}
	reverted, err := r.Revert(t.Context(), Reversal{Base: changed, Commit: changed, Message: "Undo two"}, tester)
	if err != nil {
		t.Fatal(err)
	}
	if blob, _ := r.File(t.Context(), "run.sh"); blob.Text != "echo one\n" {
		t.Fatalf("after revert run.sh = %q", blob.Text)
	}
	page, err := r.Log(t.Context(), "run.sh", 0)
	if err != nil || len(page.Commits) != 3 || page.Commits[0].SHA != reverted || page.More {
		t.Fatalf("log = %+v, %v", page, err)
	}
	if _, err := r.Revert(t.Context(), Reversal{Base: reverted, Commit: base, Message: "Undo start"}, tester); !errors.Is(err, errRoot) {
		t.Fatalf("root revert: %v", err)
	}
	listing, err := r.Tree(t.Context(), "")
	if err != nil || len(listing.Entries) != 2 || !listing.Entries[0].Dir || listing.Entries[1].Name != "run.sh" {
		t.Fatalf("tree = %+v, %v", listing, err)
	}
	if _, err := r.Tree(t.Context(), "../etc"); !errors.Is(err, errPath) {
		t.Fatalf("escape: %v", err)
	}
}

func TestBatchReadsAndLastChanged(t *testing.T) {
	r := seeded(t)
	base, _ := r.Head(t.Context())
	files, err := r.FilesAt(t.Context(), base, []string{"run.sh", "missing.nix", "pkgs/demo/default.nix"})
	if err != nil || files["run.sh"] != "echo one\n" || files["pkgs/demo/default.nix"] != "{ }\n" || len(files) != 2 {
		t.Fatalf("files = %q, %v", files, err)
	}
	if _, err := r.Commit(t.Context(), Edit{Base: base, Message: "two", Changes: []FileChange{{Path: "run.sh", Content: text("echo two\n")}}}, tester); err != nil {
		t.Fatal(err)
	}
	changed, err := r.LastChanged(t.Context(), []string{"run.sh", "pkgs/demo/default.nix"})
	if err != nil || len(changed) != 2 || changed["run.sh"].Before(changed["pkgs/demo/default.nix"]) {
		t.Fatalf("changed = %v, %v", changed, err)
	}
}

func TestRevertNeedsMessage(t *testing.T) {
	r := seeded(t)
	base, _ := r.Head(t.Context())
	if _, err := r.Revert(t.Context(), Reversal{Base: base, Commit: base, Message: "  "}, tester); !errors.Is(err, errMessage) {
		t.Fatalf("blank revert: %v", err)
	}
}
