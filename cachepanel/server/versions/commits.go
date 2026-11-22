package versions

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/repo"
)

const maxErrorBytes = 16 << 10

// ErrKnown means already evaluated.
var ErrKnown = errors.New("commit already recorded")

// BeginNewer appends a commit.
func BeginNewer(ctx context.Context, db *pgxpool.Pool, c repo.Commit) (int64, error) {
	return begin(ctx, db, c, `coalesce(max(position), 0) + 1`)
}

// BeginOlder prepends a commit.
func BeginOlder(ctx context.Context, db *pgxpool.Pool, c repo.Commit) (int64, error) {
	return begin(ctx, db, c, `coalesce(min(position), 0) - 1`)
}

func begin(ctx context.Context, db *pgxpool.Pool, c repo.Commit, position string) (int64, error) {
	var assigned int64
	err := db.QueryRow(ctx, `
		INSERT INTO commits (sha, position, subject, author, committed_at)
		SELECT $1, `+position+`, $2, $3, $4 FROM commits
		ON CONFLICT (sha) DO NOTHING
		RETURNING position`, c.SHA, c.Subject, c.Author, c.Time).Scan(&assigned)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrKnown
	}
	return assigned, err
}

func Fail(ctx context.Context, db *pgxpool.Pool, sha string, failure error) error {
	message := failure.Error()
	if len(message) > maxErrorBytes {
		message = message[len(message)-maxErrorBytes:]
	}
	_, err := db.Exec(ctx, `
		UPDATE commits SET eval_state = 'failed', eval_finished_at = now(), eval_error = $2
		WHERE sha = $1`, sha, message)
	return err
}

func finish(ctx context.Context, tx pgx.Tx, sha string, cols columns, changed int) error {
	_, err := tx.Exec(ctx, `
		UPDATE commits SET eval_state = 'done', eval_finished_at = now(), attrs = $2, failed_attrs = $3, changed = $4
		WHERE sha = $1`, sha, len(cols.attrs), cols.failed, changed)
	return err
}
