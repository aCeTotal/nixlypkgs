package release

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/repo"
)

const reloadInterval = 30 * time.Second

// Pointer tells machines what runs.
type Pointer struct {
	Profile   string    `json:"profile"`
	Title     string    `json:"title"`
	Platform  string    `json:"platform"`
	Rev       string    `json:"rev"`
	Source    string    `json:"source"`
	Tree      string    `json:"tree"`
	Path      string    `json:"path"`
	Published time.Time `json:"published"`
}

type summary struct {
	Name        string `json:"name"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Platform    string `json:"platform"`
	Published   bool   `json:"published"`
}

// Entry is a pre-encoded response body.
type Entry struct {
	Body []byte
	ETag string
}

type state struct {
	pointers map[string]Entry
	list     Entry
	archives map[string][]byte
}

// Releases serves published profiles from memory.
type Releases struct {
	db      *pgxpool.Pool
	mirror  *repo.Mirror
	current atomic.Pointer[state]
	reload  chan struct{}
}

func New(db *pgxpool.Pool, mirror *repo.Mirror) *Releases {
	r := &Releases{db: db, mirror: mirror, reload: make(chan struct{}, 1)}
	r.current.Store(&state{pointers: map[string]Entry{}, archives: map[string][]byte{}})
	return r
}

func (r *Releases) Trigger() {
	select {
	case r.reload <- struct{}{}:
	default:
	}
}

func (r *Releases) Run(ctx context.Context) error {
	for {
		if err := r.load(ctx); err != nil && ctx.Err() == nil {
			slog.Error("load releases", "error", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-r.reload:
		case <-time.After(reloadInterval):
		}
	}
}

func (r *Releases) Pointer(name string) (Entry, bool) {
	entry, found := r.current.Load().pointers[name]
	return entry, found
}

func (r *Releases) load(ctx context.Context) error {
	rows, err := r.db.Query(ctx, `
		SELECT p.name, p.title, p.description, p.platform, coalesce(p.published_tree, ''),
			coalesce(p.published_rev, ''), coalesce(p.published_at, 'epoch'), tr.archive
		FROM profiles p LEFT JOIN trees tr ON tr.hash = p.published_tree ORDER BY p.id`)
	if err != nil {
		return err
	}
	next := &state{pointers: map[string]Entry{}, archives: map[string][]byte{}}
	summaries := []summary{}
	var s summary
	var p Pointer
	var archive []byte
	_, err = pgx.ForEachRow(rows, []any{&s.Name, &s.Title, &s.Description, &s.Platform, &p.Tree, &p.Rev, &p.Published, &archive}, func() error {
		s.Published = p.Tree != "" && p.Rev != ""
		summaries = append(summaries, s)
		if !s.Published {
			return nil
		}
		p.Profile, p.Title, p.Platform = s.Name, s.Title, s.Platform
		p.Source, p.Path = r.mirror.Source(p.Rev), "/api/v1/trees/"+p.Tree+".tar.gz"
		next.archives[p.Tree] = archive
		entry, err := encode(p)
		next.pointers[s.Name] = entry
		return err
	})
	if err != nil {
		return err
	}
	if next.list, err = encode(summaries); err != nil {
		return err
	}
	r.current.Store(next)
	return nil
}

func encode(value any) (Entry, error) {
	body, err := json.Marshal(value)
	if err != nil {
		return Entry{}, err
	}
	sum := sha256.Sum256(body)
	return Entry{Body: body, ETag: `"` + hex.EncodeToString(sum[:12]) + `"`}, nil
}
