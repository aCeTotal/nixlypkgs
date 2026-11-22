package builds

import (
	"context"
	"errors"
	"log/slog"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/realtime"
)

const (
	workers     = 2
	idlePoll    = 15 * time.Second
	retryPause  = 5 * time.Second
	publishTick = 500 * time.Millisecond
)

type claimed struct {
	ID       int64
	DrvPath  string
	Name     string
	Outputs  map[string]string
	Attr     string
	Expected int
}

type job struct {
	cancel    context.CancelFunc
	cancelled atomic.Bool
	mu        sync.Mutex
	progress  Progress
}

func (j *job) set(progress Progress) {
	j.mu.Lock()
	j.progress = progress
	j.mu.Unlock()
}

// Pool builds queued versions in parallel.
type Pool struct {
	db      *pgxpool.Pool
	hub     *realtime.Hub
	files   Files
	gc      *collector
	changed func()
	wake    chan struct{}
	claimMu sync.Mutex

	mu      sync.Mutex
	running map[int64]*job
}

func NewPool(db *pgxpool.Pool, hub *realtime.Hub, files Files, changed func()) *Pool {
	return &Pool{
		db:      db,
		hub:     hub,
		files:   files,
		gc:      newCollector(),
		changed: changed,
		wake:    make(chan struct{}, workers),
		running: map[int64]*job{},
	}
}

// Run requeues, then works.
func (p *Pool) Run(ctx context.Context) error {
	if _, err := p.db.Exec(ctx, `UPDATE versions SET state = 'queued' WHERE state = 'building'`); err != nil {
		return err
	}
	if err := p.files.prepare(); err != nil {
		return err
	}
	go p.gc.run(ctx)
	var group sync.WaitGroup
	for range workers {
		group.Go(func() { p.work(ctx) })
	}
	group.Wait()
	return nil
}

// Wake nudges every idle worker.
func (p *Pool) Wake() {
	for range workers {
		select {
		case p.wake <- struct{}{}:
		default:
		}
	}
}

func (p *Pool) work(ctx context.Context) {
	for ctx.Err() == nil {
		next, found, err := p.claim(ctx)
		if err != nil {
			slog.Error("claim build", "error", err)
			sleep(ctx, retryPause)
			continue
		}
		if !found {
			p.idle(ctx)
			continue
		}
		p.build(ctx, next)
	}
}

func (p *Pool) idle(ctx context.Context) {
	select {
	case <-ctx.Done():
	case <-p.wake:
	case <-time.After(idlePoll):
	}
}

// claim skips derivations another worker builds.
func (p *Pool) claim(ctx context.Context) (claimed, bool, error) {
	p.claimMu.Lock()
	defer p.claimMu.Unlock()
	var next claimed
	err := p.db.QueryRow(ctx, `
		UPDATE versions v SET state = 'building', started_at = now(), finished_at = NULL, error = NULL, priority = false
		FROM packages p
		WHERE p.id = v.package_id AND v.id = (
			SELECT q.id FROM versions q
			WHERE q.state = 'queued'
				AND NOT EXISTS (SELECT 1 FROM versions b WHERE b.state = 'building' AND b.drv_path = q.drv_path)
			ORDER BY q.priority DESC, q.last_position DESC, q.id
			LIMIT 1 FOR UPDATE SKIP LOCKED)
		RETURNING v.id, v.drv_path, v.name, v.outputs, p.attr, coalesce(p.expected_seconds, 0)`).
		Scan(&next.ID, &next.DrvPath, &next.Name, &next.Outputs, &next.Attr, &next.Expected)
	if errors.Is(err, pgx.ErrNoRows) {
		return claimed{}, false, nil
	}
	if err != nil {
		return claimed{}, false, err
	}
	return next, true, nil
}

func (p *Pool) track(next claimed, cancel context.CancelFunc) *job {
	j := &job{cancel: cancel, progress: Progress{
		VersionID: next.ID, Attr: next.Attr, Name: next.Name, StartedAt: time.Now(), ExpectedSeconds: next.Expected,
	}}
	p.mu.Lock()
	p.running[next.ID] = j
	p.mu.Unlock()
	return j
}

func (p *Pool) untrack(id int64) {
	p.mu.Lock()
	delete(p.running, id)
	p.mu.Unlock()
}

// Snapshot lists running builds, oldest first.
func (p *Pool) Snapshot() []Progress {
	p.mu.Lock()
	snapshot := make([]Progress, 0, len(p.running))
	for _, j := range p.running {
		j.mu.Lock()
		snapshot = append(snapshot, j.progress)
		j.mu.Unlock()
	}
	p.mu.Unlock()
	slices.SortFunc(snapshot, func(a, b Progress) int { return a.StartedAt.Compare(b.StartedAt) })
	return snapshot
}

// stopJob cancels a running build.
func (p *Pool) stopJob(id int64) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	j := p.running[id]
	if j == nil {
		return false
	}
	j.cancelled.Store(true)
	j.cancel()
	return true
}

type versionEvent struct {
	ID   int64  `json:"id"`
	Attr string `json:"attr"`
}

func (p *Pool) announce(id int64, attr string) {
	p.hub.Publish(realtime.VersionChanged, versionEvent{ID: id, Attr: attr})
	p.changed()
}

func sleep(ctx context.Context, pause time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(pause):
	}
}
