package profiles

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/cache"
	"cachepanel/realtime"
	"cachepanel/repo"
	"cachepanel/signing"
	"cachepanel/source"
)

const settle = time.Second

// Rebuilder recomputes profile trees.
type Rebuilder struct {
	Deps
	trigger chan struct{}
	check   chan struct{}
}

// Deps wires a Rebuilder.
type Deps struct {
	DB        *pgxpool.Pool
	Hub       *realtime.Hub
	Mirror    *repo.Mirror
	Cache     *cache.Cache
	Signer    *signing.Store
	Source    *source.Repo
	ChecksDir string
	// PublicURL serves signature bundles to machines.
	PublicURL string
	Published func()
}

func NewRebuilder(deps Deps) *Rebuilder {
	return &Rebuilder{Deps: deps, trigger: make(chan struct{}, 1), check: make(chan struct{}, 1)}
}

// Trigger schedules a rebuild.
func (b *Rebuilder) Trigger() {
	select {
	case b.trigger <- struct{}{}:
	default:
	}
}

func (b *Rebuilder) Run(ctx context.Context) error {
	if _, err := b.DB.Exec(ctx, `
		UPDATE profiles SET
			check_state = CASE WHEN check_state = 'running' THEN 'pending' ELSE check_state END,
			stable_check_state = CASE WHEN stable_check_state = 'running' THEN 'pending' ELSE stable_check_state END
		WHERE check_state = 'running' OR stable_check_state = 'running'`); err != nil {
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
	ready, err := loadReady(ctx, b.DB)
	if err != nil {
		return err
	}
	synced, err := b.syncProfiles(ctx, ready)
	if err != nil {
		return err
	}
	specs, err := loadSpecs(ctx, b.DB)
	if err != nil {
		return err
	}
	pins := map[string]map[string]Pin{}
	changed := synced
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
	stable, err := b.stableCandidates(ctx)
	if err != nil {
		return err
	}
	if changed || stable {
		b.Hub.Publish(realtime.ProfileChanged, map[string]string{})
		b.wakeChecks()
	}
	return nil
}

// candidate stores a profile's next tree.
func (b *Rebuilder) candidate(ctx context.Context, spec Spec, rev string, pinsByRev map[string]map[string]Pin) (bool, error) {
	if rev == "" {
		return false, nil
	}
	pins, err := b.pinsAt(ctx, rev, pinsByRev)
	if err != nil {
		return false, err
	}
	hash, archive, err := Archive(Files(spec, pins))
	if err != nil {
		return false, err
	}
	if err := storeTree(ctx, b.DB, hash, archive, pins); err != nil {
		return false, err
	}
	tag, err := b.DB.Exec(ctx, `
		UPDATE profiles SET candidate_tree = $2, candidate_rev = $3, check_state = 'pending', check_error = NULL
		WHERE id = $1 AND (candidate_tree IS DISTINCT FROM $2 OR candidate_rev IS DISTINCT FROM $3)`, spec.ID, hash, rev)
	return tag.RowsAffected() > 0, err
}

// pinsAt loads each revision's pins once.
func (b *Rebuilder) pinsAt(ctx context.Context, rev string, pinsByRev map[string]map[string]Pin) (map[string]Pin, error) {
	if pins, found := pinsByRev[rev]; found {
		return pins, nil
	}
	pins, err := testingPins(ctx, b.DB, rev)
	pinsByRev[rev] = pins
	return pins, err
}

func (b *Rebuilder) wakeChecks() {
	select {
	case b.check <- struct{}{}:
	default:
	}
}
