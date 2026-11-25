package upstream

import (
	"context"

	"github.com/jackc/pgx/v5"

	"cachepanel/realtime"
)

// state is a tracking state.
type state string

const (
	stateCurrent  state = "current"
	stateUpdating state = "updating"
	stateFailed   state = "failed"
)

// outcome is one derivation's result.
type outcome struct {
	attr string
	// latestRev stays as recorded when empty.
	latestRev string
	state     state
	problem   string
	committed bool
}

func failed(attr, latestRev string, err error) outcome {
	return outcome{attr: attr, latestRev: latestRev, state: stateFailed, problem: err.Error()}
}

// seen is the last record.
type seen struct {
	LatestRev string
	State     state
	Error     string
}

func (t *Tracker) known(ctx context.Context) (map[string]seen, error) {
	rows, err := t.db.Query(ctx, `SELECT attr, coalesce(latest_rev, ''), state::text, coalesce(error, '') FROM upstreams`)
	if err != nil {
		return nil, err
	}
	known := map[string]seen{}
	var attr string
	var last seen
	_, err = pgx.ForEachRow(rows, []any{&attr, &last.LatestRev, &last.State, &last.Error}, func() error {
		known[attr] = last
		return nil
	})
	return known, err
}

// forget drops untracked derivations.
func (t *Tracker) forget(ctx context.Context, tracked []string) error {
	_, err := t.db.Exec(ctx, `DELETE FROM upstreams WHERE attr <> ALL($1::text[])`, tracked)
	return err
}

// mark flags derivations being pinned.
func (t *Tracker) mark(ctx context.Context, behind []update) error {
	if len(behind) == 0 {
		return nil
	}
	attrs := make([]string, len(behind))
	for i, each := range behind {
		attrs[i] = each.attr
	}
	_, err := t.db.Exec(ctx, `
		INSERT INTO upstreams (attr, state) SELECT unnest($1::text[]), 'updating'
		ON CONFLICT (attr) DO UPDATE SET state = 'updating', error = NULL`, attrs)
	t.hub.Publish(realtime.UpstreamChanged, map[string][]string{"attrs": attrs})
	return err
}

func (t *Tracker) record(ctx context.Context, outcomes []outcome) error {
	if len(outcomes) == 0 {
		return nil
	}
	attrs := make([]string, len(outcomes))
	revs := make([]string, len(outcomes))
	states := make([]string, len(outcomes))
	problems := make([]string, len(outcomes))
	committed := make([]bool, len(outcomes))
	for i, each := range outcomes {
		attrs[i], revs[i], states[i], problems[i], committed[i] = each.attr, each.latestRev, string(each.state), each.problem, each.committed
	}
	_, err := t.db.Exec(ctx, `
		INSERT INTO upstreams AS u (attr, latest_rev, state, error, checked_at, committed_at)
		SELECT a, nullif(r, ''), s::upstream_state, nullif(e, ''), now(), CASE WHEN c THEN now() END
		FROM unnest($1::text[], $2::text[], $3::text[], $4::text[], $5::bool[]) AS o(a, r, s, e, c)
		ON CONFLICT (attr) DO UPDATE SET latest_rev = coalesce(excluded.latest_rev, u.latest_rev),
			state = excluded.state, error = excluded.error, checked_at = excluded.checked_at,
			committed_at = coalesce(excluded.committed_at, u.committed_at)`,
		attrs, revs, states, problems, committed)
	t.hub.Publish(realtime.UpstreamChanged, map[string][]string{"attrs": attrs})
	return err
}

// retry unblocks failed revisions.
func (t *Tracker) retry(ctx context.Context) error {
	_, err := t.db.Exec(ctx, `UPDATE upstreams SET latest_rev = NULL WHERE state = 'failed'`)
	return err
}
