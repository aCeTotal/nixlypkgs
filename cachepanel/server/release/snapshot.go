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

// Branch is a release channel.
type Branch string

const (
	Stable  Branch = "stable"
	Testing Branch = "testing"
)

var branches = []Branch{Stable, Testing}

// Pointer tells machines what runs.
type Pointer struct {
	Profile   string    `json:"profile"`
	Title     string    `json:"title"`
	Platform  string    `json:"platform"`
	Branch    Branch    `json:"branch"`
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
	Stable      bool   `json:"stable"`
	Testing     bool   `json:"testing"`
}

type pointerKey struct {
	profile string
	branch  Branch
}

// released is one branch's row.
type released struct {
	tree, rev string
	at        time.Time
	archive   []byte
}

func (rel released) live() bool { return rel.tree != "" && rel.rev != "" }

// Entry is a pre-encoded response body.
type Entry struct {
	Body []byte
	ETag string
}

type state struct {
	pointers map[pointerKey]Entry
	list     Entry
	archives map[string][]byte
}

// Releases serves both branches from memory.
type Releases struct {
	db      *pgxpool.Pool
	mirror  *repo.Mirror
	current atomic.Pointer[state]
	reload  chan struct{}
}

func New(db *pgxpool.Pool, mirror *repo.Mirror) *Releases {
	r := &Releases{db: db, mirror: mirror, reload: make(chan struct{}, 1)}
	r.current.Store(&state{pointers: map[pointerKey]Entry{}, archives: map[string][]byte{}})
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

func (r *Releases) Pointer(name string, branch Branch) (Entry, bool) {
	entry, found := r.current.Load().pointers[pointerKey{name, branch}]
	return entry, found
}

func (r *Releases) load(ctx context.Context) error {
	rows, err := r.db.Query(ctx, `
		SELECT p.name, p.title, p.description, p.platform,
			coalesce(p.stable_tree, ''), coalesce(p.stable_rev, ''), coalesce(p.stable_at, 'epoch'), st.archive,
			coalesce(p.testing_tree, ''), coalesce(p.testing_rev, ''), coalesce(p.testing_at, 'epoch'), tt.archive
		FROM profiles p
			LEFT JOIN trees st ON st.hash = p.stable_tree
			LEFT JOIN trees tt ON tt.hash = p.testing_tree
		ORDER BY p.id`)
	if err != nil {
		return err
	}
	next := &state{pointers: map[pointerKey]Entry{}, archives: map[string][]byte{}}
	summaries := []summary{}
	var s summary
	var rel [2]released
	_, err = pgx.ForEachRow(rows, []any{&s.Name, &s.Title, &s.Description, &s.Platform,
		&rel[0].tree, &rel[0].rev, &rel[0].at, &rel[0].archive,
		&rel[1].tree, &rel[1].rev, &rel[1].at, &rel[1].archive}, func() error {
		s.Stable, s.Testing = rel[0].live(), rel[1].live()
		summaries = append(summaries, s)
		for i, branch := range branches {
			if err := next.add(s, branch, rel[i], r.mirror); err != nil {
				return err
			}
		}
		return nil
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

// add serves one branch's release.
func (s *state) add(profile summary, branch Branch, rel released, mirror *repo.Mirror) error {
	if !rel.live() {
		return nil
	}
	entry, err := encode(Pointer{
		Profile: profile.Name, Title: profile.Title, Platform: profile.Platform, Branch: branch,
		Rev: rel.rev, Source: mirror.Source(rel.rev), Tree: rel.tree, Path: "/api/v1/trees/" + rel.tree + ".tar.gz",
		Published: rel.at,
	})
	s.pointers[pointerKey{profile.Name, branch}] = entry
	s.archives[rel.tree] = rel.archive
	return err
}

func encode(value any) (Entry, error) {
	body, err := json.Marshal(value)
	if err != nil {
		return Entry{}, err
	}
	sum := sha256.Sum256(body)
	return Entry{Body: body, ETag: `"` + hex.EncodeToString(sum[:12]) + `"`}, nil
}
