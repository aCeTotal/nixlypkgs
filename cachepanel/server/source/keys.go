package source

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/rest"
)

var errName = rest.Unprocessable("invalid_name", "Give the key a name")

// Key may push to the source.
type Key struct {
	ID          int64     `json:"id"`
	Name        string    `json:"name"`
	Type        string    `json:"type"`
	Fingerprint string    `json:"fingerprint"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Keys stores push access.
type Keys struct {
	DB *pgxpool.Pool
}

func (k Keys) List(ctx context.Context) ([]Key, error) {
	rows, err := k.DB.Query(ctx, `SELECT id, name, key_type, fingerprint, created_at FROM ssh_keys ORDER BY id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Key])
}

func (k Keys) Add(ctx context.Context, name, line string) (Key, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Key{}, errName
	}
	parsed, err := parseKey(line)
	if err != nil {
		return Key{}, err
	}
	added := Key{Name: name, Type: parsed.Type, Fingerprint: parsed.Fingerprint}
	err = k.DB.QueryRow(ctx, `
		INSERT INTO ssh_keys (name, key_type, key_data, fingerprint) VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`, name, parsed.Type, parsed.Data, parsed.Fingerprint).Scan(&added.ID, &added.CreatedAt)
	return added, err
}

func (k Keys) Remove(ctx context.Context, id int64) error {
	tag, err := k.DB.Exec(ctx, `DELETE FROM ssh_keys WHERE id = $1`, id)
	if err == nil && tag.RowsAffected() == 0 {
		return rest.NotFound()
	}
	return err
}

// Authorized writes sshd's key list.
func (k Keys) Authorized(ctx context.Context, w io.Writer, command string) error {
	rows, err := k.DB.Query(ctx, `SELECT key_type, key_data FROM ssh_keys ORDER BY id`)
	if err != nil {
		return err
	}
	var keyType, data string
	_, err = pgx.ForEachRow(rows, []any{&keyType, &data}, func() error {
		_, err := fmt.Fprintf(w, "restrict,command=\"%s git-serve\" %s %s\n", command, keyType, data)
		return err
	})
	return err
}
