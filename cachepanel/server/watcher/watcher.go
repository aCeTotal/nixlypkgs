package watcher

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/builds"
	"cachepanel/evaluate"
	"cachepanel/realtime"
	"cachepanel/repo"
	"cachepanel/versions"
)

const (
	pollInterval  = 30 * time.Second
	forwardLimit  = 30
	backfillLimit = 120
	evalAttempts  = 2
	retryPause    = 30 * time.Second
)

// Watcher follows the branch.
type Watcher struct {
	db      *pgxpool.Pool
	hub     *realtime.Hub
	mirror  *repo.Mirror
	pool    *builds.Pool
	files   builds.Files
	changed func()
	poke    chan struct{}

	mu     sync.Mutex
	status Status
}

func New(db *pgxpool.Pool, hub *realtime.Hub, mirror *repo.Mirror, pool *builds.Pool, files builds.Files, changed func()) *Watcher {
	return &Watcher{
		db: db, hub: hub, mirror: mirror, pool: pool, files: files, changed: changed,
		poke:   make(chan struct{}, 1),
		status: Status{Phase: Idle, BackfillLimit: backfillLimit},
	}
}

// Poke starts a poll now.
func (w *Watcher) Poke() {
	select {
	case w.poke <- struct{}{}:
	default:
	}
}

func (w *Watcher) Run(ctx context.Context) error {
	if _, err := w.db.Exec(ctx, `DELETE FROM commits WHERE eval_state = 'evaluating'`); err != nil {
		return err
	}
	for ctx.Err() == nil {
		if w.cycle(ctx) {
			continue
		}
		select {
		case <-ctx.Done():
		case <-w.poke:
		case <-time.After(pollInterval):
		}
	}
	return nil
}

type settings struct {
	paused bool
	steps  int
	done   bool
}

// cycle reports pending backfill.
func (w *Watcher) cycle(ctx context.Context) bool {
	var current settings
	err := w.db.QueryRow(ctx, `SELECT paused, backfill_steps, backfill_done FROM watcher`).
		Scan(&current.paused, &current.steps, &current.done)
	if err != nil {
		w.fail(ctx, err)
		return false
	}
	w.update(func(s *Status) { s.BackfillSteps, s.BackfillDone = current.steps, current.done })
	if current.paused {
		w.update(func(s *Status) { s.Phase, s.Commit = Paused, nil })
		return false
	}
	if err := w.forward(ctx); err != nil {
		w.fail(ctx, err)
		return false
	}
	more := false
	if !current.done {
		more, err = w.backfill(ctx, current.steps)
	}
	if err != nil {
		w.fail(ctx, err)
		return false
	}
	if !more {
		w.update(func(s *Status) { s.Phase, s.Commit, s.Started = Idle, nil, nil })
	}
	return more
}

func (w *Watcher) fail(ctx context.Context, err error) {
	if ctx.Err() != nil {
		return
	}
	slog.Error("watcher", "error", err)
	w.update(func(s *Status) { s.Phase, s.Commit, s.LastError = Idle, nil, err.Error() })
}

func (w *Watcher) forward(ctx context.Context) error {
	w.working(Fetching, nil)
	head, err := w.mirror.Fetch(ctx)
	if err != nil {
		return err
	}
	now := time.Now()
	w.update(func(s *Status) { s.Head, s.LastPoll, s.LastError = head, &now, "" })
	var newest string
	err = w.db.QueryRow(ctx, `SELECT sha FROM commits ORDER BY position DESC LIMIT 1`).Scan(&newest)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if newest == head {
		return nil
	}
	commits, err := w.mirror.Since(ctx, newest, head, forwardLimit)
	if err != nil {
		return err
	}
	for _, c := range commits {
		if err := w.advance(ctx, c); err != nil {
			return err
		}
	}
	return nil
}

func (w *Watcher) advance(ctx context.Context, c repo.Commit) error {
	position, err := versions.BeginNewer(ctx, w.db, c)
	if errors.Is(err, versions.ErrKnown) {
		return nil
	}
	if err != nil {
		return err
	}
	w.working(Evaluating, &c)
	w.publishCommit(c.SHA)
	attrs, err := w.evaluate(ctx, c.SHA)
	if err != nil {
		return w.failCommit(ctx, c.SHA, err)
	}
	evicted, err := versions.Advance(ctx, w.db, c.SHA, position, attrs)
	if err != nil {
		return w.failCommit(ctx, c.SHA, err)
	}
	w.pool.Forget(evicted)
	w.syncPinnable(ctx, c.SHA)
	w.settle(ctx, c.SHA)
	return nil
}

func (w *Watcher) evaluate(ctx context.Context, sha string) ([]evaluate.Attr, error) {
	var attrs []evaluate.Attr
	var err error
	for attempt := range evalAttempts {
		if attempt > 0 {
			sleepFor(ctx, retryPause)
		}
		attrs, err = evaluate.Packages(ctx, w.mirror.FlakeRef(sha), w.files.DrvRoots())
		if err == nil || ctx.Err() != nil {
			return attrs, err
		}
	}
	return nil, err
}

// failCommit records, then continues.
func (w *Watcher) failCommit(ctx context.Context, sha string, failure error) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	slog.Warn("evaluation failed", "commit", sha, "error", failure)
	if err := versions.Fail(ctx, w.db, sha, failure); err != nil {
		return err
	}
	w.publishCommit(sha)
	return nil
}

func (w *Watcher) settle(ctx context.Context, sha string) {
	if err := w.files.PruneDrvRoots(ctx, w.db); err != nil {
		slog.Warn("prune derivation roots", "error", err)
	}
	w.pool.Wake()
	w.publishCommit(sha)
	w.hub.Publish(realtime.PackageChanged, map[string]string{})
	w.changed()
}

func (w *Watcher) publishCommit(sha string) {
	w.hub.Publish(realtime.CommitChanged, map[string]string{"sha": sha})
}

func sleepFor(ctx context.Context, pause time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(pause):
	}
}
