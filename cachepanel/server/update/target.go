package update

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const panelAttr = "cachepanel"

// Target is the newest cached panel.
type Target struct {
	Rev string `json:"rev"`
	Out string `json:"out"`
}

// newest follows the newest evaluated commit only.
func newest(ctx context.Context, db *pgxpool.Pool) (Target, bool, error) {
	var t Target
	err := db.QueryRow(ctx, `
		SELECT c.sha, v.outputs->>'out'
		FROM (SELECT sha, position FROM commits WHERE eval_state = 'done' ORDER BY position DESC LIMIT 1) c
			JOIN packages p ON p.attr = $1
			JOIN versions v ON v.package_id = p.id AND c.position BETWEEN v.first_position AND v.last_position
		WHERE v.state = 'cached'`, panelAttr).Scan(&t.Rev, &t.Out)
	if errors.Is(err, pgx.ErrNoRows) {
		return Target{}, false, nil
	}
	return t, err == nil, err
}

// running is this process's store path.
func running() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(exe)
	if err != nil {
		return "", err
	}
	return storePath(resolved), nil
}

// storePath trims a file to its store entry.
func storePath(path string) string {
	parts := strings.SplitN(path, "/", 5)
	if len(parts) < 4 || parts[1] != "nix" || parts[2] != "store" {
		return path
	}
	return strings.Join(parts[:4], "/")
}
