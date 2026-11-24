package update

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/realtime"
	"cachepanel/watcher"
)

const tick = 15 * time.Second

// Updater asks root to rebuild the panel once the server is idle.
type Updater struct {
	DB      *pgxpool.Pool
	Hub     *realtime.Hub
	Watcher *watcher.Watcher
	// Dir is shared with the root updater; empty disables updates.
	Dir string

	mu     sync.Mutex
	idle   bool
	status Status
}

func (u *Updater) Run(ctx context.Context) error {
	if u.Dir == "" {
		return nil
	}
	self, err := running()
	if err != nil {
		return err
	}
	ticker := time.NewTicker(tick)
	defer ticker.Stop()
	for {
		if err := u.step(ctx, self); err != nil && ctx.Err() == nil {
			slog.Error("panel update", "error", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func (u *Updater) step(ctx context.Context, self string) error {
	idle, err := u.quiet(ctx)
	if err != nil {
		return err
	}
	if err := u.markIdle(idle); err != nil {
		return err
	}
	var status Status
	if _, err := readJSON(filepath.Join(u.Dir, statusFile), &status); err != nil {
		return err
	}
	u.remember(idle, status)
	return u.request(ctx, self, status)
}

// quiet means nothing a restart would kill.
func (u *Updater) quiet(ctx context.Context) (bool, error) {
	if phase := u.Watcher.Status().Phase; phase != watcher.Idle && phase != watcher.Paused {
		return false, nil
	}
	var quiet bool
	err := u.DB.QueryRow(ctx, `
		SELECT NOT EXISTS (SELECT 1 FROM versions WHERE state IN ('queued', 'building'))
			AND NOT EXISTS (SELECT 1 FROM profiles
				WHERE check_state IN ('pending', 'running') OR stable_check_state IN ('pending', 'running'))`).Scan(&quiet)
	return quiet, err
}

// markIdle keeps a fresh file while idle.
func (u *Updater) markIdle(idle bool) error {
	path := filepath.Join(u.Dir, idleFile)
	if idle {
		return writeAtomic(path, nil)
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

func (u *Updater) remember(idle bool, status Status) {
	u.mu.Lock()
	changed := u.idle != idle || u.status != status
	u.idle, u.status = idle, status
	u.mu.Unlock()
	if changed {
		u.Hub.Publish(realtime.UpdateChanged, map[string]string{})
	}
}

// request names a new panel once.
func (u *Updater) request(ctx context.Context, self string, status Status) error {
	var enabled bool
	if err := u.DB.QueryRow(ctx, `SELECT enabled FROM panel_update`).Scan(&enabled); err != nil || !enabled {
		return err
	}
	target, found, err := newest(ctx, u.DB)
	if err != nil || !found || target.Out == self {
		return err
	}
	if status.Target == target.Out && status.Phase == Failed {
		return nil
	}
	path := filepath.Join(u.Dir, requestFile)
	want := Request{Rev: target.Rev, Target: target.Out}
	var current Request
	if _, err := readJSON(path, &current); err != nil || current == want {
		return err
	}
	body, err := json.Marshal(want)
	if err != nil {
		return err
	}
	slog.Info("requesting panel update", "rev", target.Rev, "target", target.Out)
	return writeAtomic(path, body)
}

func (u *Updater) snapshot() (bool, Status) {
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.idle, u.status
}
