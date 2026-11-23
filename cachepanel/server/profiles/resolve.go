package profiles

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// readyCommit has nothing left building.
const readyCommit = `
	SELECT c.sha FROM commits c
	WHERE c.eval_state = 'done' AND NOT EXISTS (
		SELECT 1 FROM versions v JOIN packages p ON p.id = v.package_id
		WHERE p.auto_build AND v.state IN ('queued', 'building')
			AND c.position BETWEEN v.first_position AND v.last_position)
	ORDER BY c.position DESC LIMIT 1`

func loadReady(ctx context.Context, db *pgxpool.Pool) (string, error) {
	var sha string
	err := db.QueryRow(ctx, readyCommit).Scan(&sha)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	return sha, err
}

// loadPins maps pins to outputs.
func loadPins(ctx context.Context, db *pgxpool.Pool) (map[string]string, error) {
	rows, err := db.Query(ctx, `
		SELECT p.attr, v.outputs->>'out' FROM packages p JOIN versions v ON v.id = p.selected_version_id
		WHERE p.pinnable AND v.state = 'cached' AND v.outputs ? 'out'`)
	if err != nil {
		return nil, err
	}
	pins := map[string]string{}
	var attr, out string
	_, err = pgx.ForEachRow(rows, []any{&attr, &out}, func() error {
		pins[attr] = out
		return nil
	})
	return pins, err
}

func loadSpecs(ctx context.Context, db *pgxpool.Pool) ([]Spec, error) {
	rows, err := db.Query(ctx, `
		SELECT p.id, p.name, p.platform, p.kernel, coalesce(p.pinned_sha, ''), p.packages,
			coalesce((SELECT json_agg(json_build_object('slug', m.slug, 'source', m.source) ORDER BY m.position)
				FROM modules m WHERE m.required
					OR EXISTS (SELECT 1 FROM profile_modules pm WHERE pm.profile_id = p.id AND pm.module_id = m.id)), '[]')
		FROM profiles p ORDER BY p.id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Spec, error) {
		var spec Spec
		err := row.Scan(&spec.ID, &spec.Name, &spec.Platform, &spec.Kernel, &spec.Pinned, &spec.Packages, &spec.Modules)
		return spec, err
	})
}
