package editor

import (
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/logtail"
	"cachepanel/repo"
	"cachepanel/rest"
)

const (
	indexTimeout = 5 * time.Minute
	stderrKeep   = 8 << 10
)

var errNoCommit = rest.Conflict("no_commit", "The panel has not evaluated any commit yet")

// Index serves completions per revision.
type Index struct {
	db     *pgxpool.Pool
	mirror *repo.Mirror
	dir    *os.Root
	mu     sync.Mutex
}

// NewIndex keeps built indexes in dir.
func NewIndex(db *pgxpool.Pool, mirror *repo.Mirror, dir string) (*Index, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, err
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		return nil, err
	}
	return &Index{db: db, mirror: mirror, dir: root}, nil
}

func (x *Index) serve(w http.ResponseWriter, r *http.Request) error {
	var sha string
	err := x.db.QueryRow(r.Context(), `SELECT sha FROM commits WHERE eval_state = 'done' ORDER BY position DESC LIMIT 1`).Scan(&sha)
	if errors.Is(err, pgx.ErrNoRows) {
		return errNoCommit
	}
	if err != nil {
		return err
	}
	if r.Header.Get("If-None-Match") == `"`+sha+`"` {
		w.WriteHeader(http.StatusNotModified)
		return nil
	}
	body, err := x.build(r.Context(), sha)
	if err != nil {
		return err
	}
	header := w.Header()
	header.Set("Content-Type", "application/json")
	header.Set("Content-Encoding", "gzip")
	header.Set("ETag", `"`+sha+`"`)
	header.Set("Cache-Control", "private, no-cache")
	_, err = w.Write(body)
	return err
}

// build evaluates one revision's index, once.
func (x *Index) build(ctx context.Context, sha string) ([]byte, error) {
	x.mu.Lock()
	defer x.mu.Unlock()
	name := sha + ".json.gz"
	if body, err := x.dir.ReadFile(name); err == nil {
		return body, nil
	}
	ctx, cancel := context.WithTimeout(ctx, indexTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", x.mirror.FlakeRef(sha)+"#lib.nixlyos.editor", "--apply", `editor: editor "x86_64-linux"`)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("editor index: %w\n%s", err, stderr.String())
	}
	var packed bytes.Buffer
	compressor := gzip.NewWriter(&packed)
	if _, err := compressor.Write(out); err != nil {
		return nil, err
	}
	if err := compressor.Close(); err != nil {
		return nil, err
	}
	// Older revisions are never requested.
	stale, err := fs.Glob(x.dir.FS(), "*.json.gz")
	if err != nil {
		return nil, err
	}
	for _, old := range stale {
		if err := x.dir.Remove(old); err != nil {
			return nil, err
		}
	}
	return packed.Bytes(), x.dir.WriteFile(name, packed.Bytes(), 0o600)
}
