package watcher

import (
	"context"
	"errors"
	"log/slog"

	"github.com/jackc/pgx/v5"

	"cachepanel/evaluate"
	"cachepanel/realtime"
)

// syncMeta stores what a commit offers profiles.
func (w *Watcher) syncMeta(ctx context.Context, sha string) {
	meta, err := evaluate.ReadMeta(ctx, w.mirror.FlakeRef(sha))
	if err != nil {
		slog.Info("no profile metadata", "commit", sha, "error", err)
		return
	}
	if _, err := w.db.Exec(ctx, `UPDATE packages SET pinnable = attr = ANY($1)`, meta.Pinnable); err != nil {
		slog.Error("store pinnable packages", "error", err)
		return
	}
	if _, err := w.db.Exec(ctx, `UPDATE commits SET kernels = $2 WHERE sha = $1`, sha, meta.Kernels); err != nil {
		slog.Error("store kernel catalogue", "error", err)
		return
	}
	w.hub.Publish(realtime.PackageChanged, map[string]string{})
}

// catchUp reads the newest commit's catalogue if it predates one.
func (w *Watcher) catchUp(ctx context.Context) {
	var sha string
	err := w.db.QueryRow(ctx, `
		SELECT sha FROM (SELECT sha, kernels FROM commits WHERE eval_state = 'done' ORDER BY position DESC LIMIT 1) newest
		WHERE kernels IS NULL`).Scan(&sha)
	if errors.Is(err, pgx.ErrNoRows) {
		return
	}
	if err != nil {
		slog.Error("find commit without catalogue", "error", err)
		return
	}
	w.syncMeta(ctx, sha)
}
