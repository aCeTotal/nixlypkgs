package auth

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// EnsureAdmin creates the first user only.
func EnsureAdmin(ctx context.Context, db *pgxpool.Pool, username, hash string) error {
	if username == "" {
		return nil
	}
	_, err := db.Exec(ctx, `
		INSERT INTO users (username, password_hash)
		SELECT $1, $2 WHERE NOT EXISTS (SELECT 1 FROM users)`, username, hash)
	return err
}
