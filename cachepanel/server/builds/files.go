package builds

import (
	"context"
	"encoding/json"
	"log/slog"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Files lays out state.
type Files struct {
	dir string
}

func NewFiles(stateDir string) Files {
	return Files{dir: stateDir}
}

func (f Files) Root(id int64) string {
	return filepath.Join(f.dir, "gcroots", strconv.FormatInt(id, 10))
}

func (f Files) Log(id int64) string {
	return filepath.Join(f.dir, "logs", strconv.FormatInt(id, 10)+".log")
}

// DrvRoots keeps evaluated derivations alive.
func (f Files) DrvRoots() string {
	return filepath.Join(f.dir, "drv-roots")
}

func (f Files) prepare() error {
	for _, dir := range []string{"gcroots", "logs", "drv-roots"} {
		if err := os.MkdirAll(filepath.Join(f.dir, dir), 0o750); err != nil {
			return err
		}
	}
	return nil
}

func (f Files) removeRoot(id int64) {
	if err := os.RemoveAll(f.Root(id)); err != nil {
		slog.Warn("remove gcroot", "version", id, "error", err)
	}
}

// Forget drops roots and log.
func (f Files) Forget(id int64) {
	f.removeRoot(id)
	if err := os.Remove(f.Log(id)); err != nil && !os.IsNotExist(err) {
		slog.Warn("remove build log", "version", id, "error", err)
	}
}

// PruneDrvRoots unroots derivations no version uses.
func (f Files) PruneDrvRoots(ctx context.Context, db *pgxpool.Pool) error {
	rows, err := db.Query(ctx, `SELECT DISTINCT drv_path FROM versions`)
	if err != nil {
		return err
	}
	kept, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return err
	}
	keep := map[string]bool{}
	for _, drv := range kept {
		keep[filepath.Base(drv)] = true
	}
	entries, err := os.ReadDir(f.DrvRoots())
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if keep[entry.Name()] {
			continue
		}
		if err := os.Remove(filepath.Join(f.DrvRoots(), entry.Name())); err != nil {
			return err
		}
	}
	return nil
}

// closureBytes sums the output closures.
func (p *Pool) closureBytes(ctx context.Context, next claimed) int64 {
	outputs := slices.Sorted(maps.Values(next.Outputs))
	out, err := exec.CommandContext(ctx, "nix", append([]string{"path-info", "--json", "--recursive"}, outputs...)...).Output()
	if err != nil {
		slog.Warn("closure size", "version", next.ID, "error", err)
		return 0
	}
	var paths map[string]struct {
		NarSize int64 `json:"narSize"`
	}
	if err := json.Unmarshal(out, &paths); err != nil {
		slog.Warn("closure size", "version", next.ID, "error", err)
		return 0
	}
	var total int64
	for _, info := range paths {
		total += info.NarSize
	}
	return total
}
