package versions

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/evaluate"
)

// Extend applies a backfilled commit.
func Extend(ctx context.Context, db *pgxpool.Pool, sha string, position int64, attrs []evaluate.Attr) (bool, error) {
	cols, err := split(attrs)
	if err != nil {
		return false, err
	}
	var complete bool
	err = pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		changed, err := prepend(ctx, tx, sha, position, cols)
		if err != nil {
			return err
		}
		if err := finish(ctx, tx, sha, cols, changed); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `
			SELECT NOT EXISTS (
				SELECT 1 FROM packages p
				WHERE p.present AND (SELECT count(*) FROM versions v WHERE v.package_id = p.id) < $1)`, Keep).
			Scan(&complete)
	})
	return complete, err
}

// prepend adds older versions.
func prepend(ctx context.Context, tx pgx.Tx, sha string, position int64, cols columns) (int, error) {
	args := []any{cols.good, cols.drvs, cols.names, cols.outputs, sha, position}
	if _, err := tx.Exec(ctx, `WITH `+incoming+`,
		oldest AS (
			SELECT DISTINCT ON (v.package_id) v.id, v.package_id, v.drv_path
			FROM versions v JOIN known k ON k.package_id = v.package_id
			ORDER BY v.package_id, v.last_position)
		UPDATE versions v SET first_sha = $5, first_position = $6
		FROM oldest o JOIN known k ON k.package_id = o.package_id
		WHERE v.id = o.id AND o.drv_path = k.drv_path`, args...); err != nil {
		return 0, err
	}
	args = append(args, Keep)
	tag, err := tx.Exec(ctx, `WITH `+incoming+`,
		counts AS (
			SELECT v.package_id, count(*) AS total FROM versions v
			WHERE v.package_id IN (SELECT package_id FROM known) GROUP BY v.package_id)
		INSERT INTO versions (package_id, drv_path, name, outputs, first_sha, last_sha, first_position, last_position, state, queued_at)
		SELECT k.package_id, k.drv_path, k.name, k.outputs, $5, $5, $6, $6, `+queuedState+`
		FROM known k
			JOIN packages p ON p.id = k.package_id AND p.present
			LEFT JOIN counts c ON c.package_id = k.package_id
		WHERE coalesce(c.total, 0) < $7
			AND NOT EXISTS (SELECT 1 FROM versions v WHERE v.package_id = k.package_id AND v.drv_path = k.drv_path)
		ON CONFLICT (package_id, drv_path) DO NOTHING`, args...)
	return int(tag.RowsAffected()), err
}
