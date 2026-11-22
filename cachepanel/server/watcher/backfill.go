package watcher

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"

	"cachepanel/repo"
	"cachepanel/versions"
)

// backfill evaluates one older commit.
func (w *Watcher) backfill(ctx context.Context, steps int) (bool, error) {
	if steps >= backfillLimit {
		return false, w.endBackfill(ctx)
	}
	var oldest string
	err := w.db.QueryRow(ctx, `SELECT sha FROM commits ORDER BY position LIMIT 1`).Scan(&oldest)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	parents, err := w.mirror.Parents(ctx, oldest, 1)
	if err != nil {
		return false, err
	}
	if len(parents) == 0 {
		return false, w.endBackfill(ctx)
	}
	c := parents[0]
	position, err := versions.BeginOlder(ctx, w.db, c)
	if errors.Is(err, versions.ErrKnown) {
		return false, w.endBackfill(ctx)
	}
	if err != nil {
		return false, err
	}
	w.working(Backfilling, &c)
	w.publishCommit(c.SHA)
	complete, err := w.extend(ctx, c, position)
	if err != nil {
		return false, err
	}
	steps++
	if _, err := w.db.Exec(ctx, `UPDATE watcher SET backfill_steps = $1, backfill_done = $2`, steps, complete); err != nil {
		return false, err
	}
	w.update(func(s *Status) { s.BackfillSteps, s.BackfillDone = steps, complete })
	w.settle(ctx, c.SHA)
	return !complete && steps < backfillLimit, nil
}

// extend reports backfill completion.
func (w *Watcher) extend(ctx context.Context, c repo.Commit, position int64) (bool, error) {
	attrs, err := w.evaluate(ctx, c.SHA)
	if err != nil {
		return false, w.failCommit(ctx, c.SHA, err)
	}
	complete, err := versions.Extend(ctx, w.db, c.SHA, position, attrs)
	if err != nil {
		return false, w.failCommit(ctx, c.SHA, err)
	}
	return complete, nil
}

func (w *Watcher) endBackfill(ctx context.Context) error {
	if _, err := w.db.Exec(ctx, `UPDATE watcher SET backfill_done = true`); err != nil {
		return err
	}
	w.update(func(s *Status) { s.BackfillDone = true })
	return nil
}
