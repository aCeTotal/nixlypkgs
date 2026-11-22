package versions

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/evaluate"
)

// Keep is versions per package.
const Keep = 3

type Evicted struct {
	ID      int64
	DrvPath string
}

const incoming = `incoming AS (
	SELECT * FROM unnest($1::text[], $2::text[], $3::text[], $4::jsonb[]) AS t(attr, drv_path, name, outputs)),
known AS (
	SELECT p.id AS package_id, p.auto_build, i.* FROM incoming i JOIN packages p ON p.attr = i.attr)`

const newest = `newest AS (
	SELECT DISTINCT ON (v.package_id) v.id, v.package_id, v.drv_path
	FROM versions v JOIN known k ON k.package_id = v.package_id
	ORDER BY v.package_id, v.last_position DESC)`

const queuedState = `CASE WHEN k.auto_build THEN 'queued'::build_state ELSE 'pending'::build_state END,
	CASE WHEN k.auto_build THEN now() END`

// Advance applies the newest commit's evaluation.
func Advance(ctx context.Context, db *pgxpool.Pool, sha string, position int64, attrs []evaluate.Attr) ([]Evicted, error) {
	cols, err := split(attrs)
	if err != nil {
		return nil, err
	}
	var evicted []Evicted
	err = pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		if err := syncPackages(ctx, tx, cols); err != nil {
			return err
		}
		changed, err := record(ctx, tx, sha, position, cols)
		if err != nil {
			return err
		}
		if evicted, err = retain(ctx, tx); err != nil {
			return err
		}
		return finish(ctx, tx, sha, cols, changed)
	})
	return evicted, err
}

func syncPackages(ctx context.Context, tx pgx.Tx, cols columns) error {
	if _, err := tx.Exec(ctx, `
		INSERT INTO packages (attr, eval_error)
		SELECT attr, nullif(failure, '') FROM unnest($1::text[], $2::text[]) AS t(attr, failure)
		ON CONFLICT (attr) DO UPDATE SET eval_error = EXCLUDED.eval_error, present = true`,
		cols.attrs, cols.errors); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE packages SET present = false WHERE present AND attr <> ALL($1)`, cols.attrs)
	return err
}

// record extends runs, adds derivations.
func record(ctx context.Context, tx pgx.Tx, sha string, position int64, cols columns) (int, error) {
	args := []any{cols.good, cols.drvs, cols.names, cols.outputs, sha, position}
	if _, err := tx.Exec(ctx, `WITH `+incoming+`, `+newest+`
		UPDATE versions v SET last_sha = $5, last_position = $6
		FROM newest n JOIN known k ON k.package_id = n.package_id
		WHERE v.id = n.id AND n.drv_path = k.drv_path`, args...); err != nil {
		return 0, err
	}
	tag, err := tx.Exec(ctx, `WITH `+incoming+`, `+newest+`
		INSERT INTO versions (package_id, drv_path, name, outputs, first_sha, last_sha, first_position, last_position, state, queued_at)
		SELECT k.package_id, k.drv_path, k.name, k.outputs, $5, $5, $6, $6, `+queuedState+`
		FROM known k LEFT JOIN newest n ON n.package_id = k.package_id
		WHERE n.drv_path IS DISTINCT FROM k.drv_path
		ON CONFLICT (package_id, drv_path) DO UPDATE SET
			first_sha = EXCLUDED.first_sha, last_sha = EXCLUDED.last_sha,
			first_position = EXCLUDED.first_position, last_position = EXCLUDED.last_position`, args...)
	return int(tag.RowsAffected()), err
}

// retain evicts beyond Keep, sparing pins.
func retain(ctx context.Context, tx pgx.Tx) ([]Evicted, error) {
	rows, err := tx.Query(ctx, `
		DELETE FROM versions v USING (
			SELECT id FROM (
				SELECT id, row_number() OVER (PARTITION BY package_id ORDER BY last_position DESC) AS rank FROM versions
			) ranked WHERE rank > $1
		) old
		WHERE v.id = old.id
			AND NOT EXISTS (SELECT 1 FROM packages p WHERE p.selected_version_id = v.id)
			AND NOT EXISTS (
				SELECT 1 FROM profiles t JOIN commits c ON c.sha = t.pinned_sha
				WHERE c.position BETWEEN v.first_position AND v.last_position)
		RETURNING v.id, v.drv_path`, Keep)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Evicted])
}
