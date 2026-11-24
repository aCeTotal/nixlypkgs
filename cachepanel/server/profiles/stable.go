package profiles

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// stableInputs build a stable candidate.
type stableInputs struct {
	ID          int64
	Rev         string
	Base        []byte
	TestingTree string
	TestingRev  string
	Testing     []byte
	StableRev   string
	Stable      []byte
}

// stableCandidates renders approved bases.
func (b *Rebuilder) stableCandidates(ctx context.Context) (bool, error) {
	pins, err := stablePins(ctx, b.DB)
	if err != nil {
		return false, err
	}
	rows, err := b.DB.Query(ctx, `
		SELECT p.id, p.base_rev, bt.archive, coalesce(p.testing_tree, ''), coalesce(p.testing_rev, ''), tt.archive,
			coalesce(p.stable_rev, ''), st.archive
		FROM profiles p
			JOIN trees bt ON bt.hash = p.base_tree
			LEFT JOIN trees tt ON tt.hash = p.testing_tree
			LEFT JOIN trees st ON st.hash = p.stable_tree
		WHERE p.base_rev IS NOT NULL`)
	if err != nil {
		return false, err
	}
	inputs, err := pgx.CollectRows(rows, pgx.RowToStructByPos[stableInputs])
	if err != nil {
		return false, err
	}
	changed := false
	for _, in := range inputs {
		moved, err := b.stableCandidate(ctx, in, pins)
		if err != nil {
			return false, err
		}
		changed = changed || moved
	}
	return changed, nil
}

func (b *Rebuilder) stableCandidate(ctx context.Context, in stableInputs, pins map[string]Pin) (bool, error) {
	files, err := readArchive(in.Base)
	if err != nil {
		return false, err
	}
	hash, archive, err := Archive(withPins(files, pins))
	if err != nil {
		return false, err
	}
	current, err := sourceHash(in.Stable)
	if err != nil {
		return false, err
	}
	if in.Rev == in.StableRev && hash == current {
		_, err := b.DB.Exec(ctx, `
			UPDATE profiles SET stable_candidate_tree = NULL, stable_check_state = NULL
			WHERE id = $1 AND stable_candidate_tree IS NOT NULL`, in.ID)
		return false, err
	}
	tested, err := sourceHash(in.Testing)
	if err != nil {
		return false, err
	}
	if in.Rev == in.TestingRev && hash == tested {
		return b.promote(ctx, in)
	}
	if err := storeTree(ctx, b.DB, hash, archive, pins); err != nil {
		return false, err
	}
	tag, err := b.DB.Exec(ctx, `
		UPDATE profiles SET stable_candidate_tree = $2, stable_check_state = 'pending', stable_check_error = NULL
		WHERE id = $1 AND stable_candidate_tree IS DISTINCT FROM $2`, in.ID, hash)
	return tag.RowsAffected() > 0, err
}

// promote reuses testing's signed tree.
func (b *Rebuilder) promote(ctx context.Context, in stableInputs) (bool, error) {
	tag, err := b.DB.Exec(ctx, `
		UPDATE profiles SET stable_tree = $2, stable_rev = $3, stable_at = now(),
			stable_candidate_tree = NULL, stable_check_state = NULL, stable_check_error = NULL
		WHERE id = $1 AND (stable_tree, stable_rev) IS DISTINCT FROM ($2, $3)`, in.ID, in.TestingTree, in.TestingRev)
	if err != nil || tag.RowsAffected() == 0 {
		return false, err
	}
	b.Published()
	return true, nil
}
