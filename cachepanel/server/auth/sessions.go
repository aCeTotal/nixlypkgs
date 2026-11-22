package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	sessionCookie  = "cachepanel_session"
	sessionTTL     = 7 * 24 * time.Hour
	sessionRefresh = time.Hour
)

type session struct {
	User User
	CSRF string
}

type sessions struct {
	db *pgxpool.Pool
}

// The database stores token hashes only.
func tokenHash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

func (s sessions) create(ctx context.Context, userID int64) (string, string, error) {
	token, csrf := rand.Text(), rand.Text()
	_, err := s.db.Exec(ctx, `
		INSERT INTO sessions (token_hash, user_id, csrf, expires_at)
		VALUES ($1, $2, $3, now() + make_interval(secs => $4))`,
		tokenHash(token), userID, csrf, sessionTTL.Seconds())
	return token, csrf, err
}

// lookup slides the expiry hourly.
func (s sessions) lookup(ctx context.Context, token string) (session, error) {
	var current session
	var expires time.Time
	err := s.db.QueryRow(ctx, `
		SELECT u.id, u.username, s.csrf, s.expires_at
		FROM sessions s JOIN users u ON u.id = s.user_id
		WHERE s.token_hash = $1 AND s.expires_at > now()`, tokenHash(token)).
		Scan(&current.User.ID, &current.User.Username, &current.CSRF, &expires)
	if err != nil || time.Until(expires) > sessionTTL-sessionRefresh {
		return current, err
	}
	_, err = s.db.Exec(ctx, `UPDATE sessions SET expires_at = now() + make_interval(secs => $2) WHERE token_hash = $1`,
		tokenHash(token), sessionTTL.Seconds())
	return current, err
}

func (s sessions) delete(ctx context.Context, token string) error {
	_, err := s.db.Exec(ctx, `DELETE FROM sessions WHERE token_hash = $1`, tokenHash(token))
	return err
}

func (s sessions) revokeOthers(ctx context.Context, userID int64, keep string) error {
	_, err := s.db.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1 AND token_hash <> $2`, userID, tokenHash(keep))
	return err
}

func (s sessions) purge(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `DELETE FROM sessions WHERE expires_at < now()`)
	return err
}
