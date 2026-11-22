package profiles

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/realtime"
	"cachepanel/repo"
)

const settle = time.Second

// Rebuilder recomputes profile trees.
type Rebuilder struct {
	db        *pgxpool.Pool
	hub       *realtime.Hub
	mirror    *repo.Mirror
	checksDir string
	published func()
	trigger   chan struct{}
	check     chan struct{}
}

func NewRebuilder(db *pgxpool.Pool, hub *realtime.Hub, mirror *repo.Mirror, checksDir string, published func()) *Rebuilder {
	return &Rebuilder{
		db: db, hub: hub, mirror: mirror, checksDir: checksDir, published: published,
		trigger: make(chan struct{}, 1),
		check:   make(chan struct{}, 1),
	}
}

// Trigger schedules a rebuild.
func (b *Rebuilder) Trigger() {
	select {
	case b.trigger <- struct{}{}:
	default:
	}
}

func (b *Rebuilder) Run(ctx context.Context) error {
	if _, err := b.db.Exec(ctx, `UPDATE profiles SET check_state = 'pending' WHERE check_state = 'running'`); err != nil {
		return err
	}
	go b.runChecks(ctx)
	b.Trigger()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-b.trigger:
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(settle):
		}
		if err := b.rebuild(ctx); err != nil && ctx.Err() == nil {
			slog.Error("rebuild profile trees", "error", err)
		}
	}
}

func (b *Rebuilder) rebuild(ctx context.Context) error {
	specs, err := loadSpecs(ctx, b.db)
	if err != nil {
		return err
	}
	ready, err := loadReady(ctx, b.db)
	if err != nil {
		return err
	}
	pins, err := loadPins(ctx, b.db)
	if err != nil {
		return err
	}
	changed := false
	for _, spec := range specs {
		rev := ready
		if spec.Pinned != "" {
			rev = spec.Pinned
		}
		moved, err := b.candidate(ctx, spec, rev, pins)
		if err != nil {
			return err
		}
		changed = changed || moved
	}
	if changed {
		b.hub.Publish(realtime.ProfileChanged, map[string]string{})
		b.wakeChecks()
	}
	return nil
}

// candidate stores a profile's next tree.
func (b *Rebuilder) candidate(ctx context.Context, spec Spec, rev string, pins map[string]string) (bool, error) {
	if rev == "" {
		return false, nil
	}
	hash, archive, err := Archive(Files(spec, pins))
	if err != nil {
		return false, err
	}
	if _, err := b.db.Exec(ctx, `INSERT INTO trees (hash, archive) VALUES ($1, $2) ON CONFLICT DO NOTHING`, hash, archive); err != nil {
		return false, err
	}
	tag, err := b.db.Exec(ctx, `
		UPDATE profiles SET candidate_tree = $2, candidate_rev = $3, check_state = 'pending', check_error = NULL
		WHERE id = $1 AND (candidate_tree IS DISTINCT FROM $2 OR candidate_rev IS DISTINCT FROM $3)`, spec.ID, hash, rev)
	return tag.RowsAffected() > 0, err
}

func (b *Rebuilder) wakeChecks() {
	select {
	case b.check <- struct{}{}:
	default:
	}
}
