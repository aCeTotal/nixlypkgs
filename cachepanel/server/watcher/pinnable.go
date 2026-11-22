package watcher

import (
	"context"
	"log/slog"

	"cachepanel/evaluate"
	"cachepanel/realtime"
)

// syncPinnable marks packages profiles may pin.
func (w *Watcher) syncPinnable(ctx context.Context, sha string) {
	pinnable, err := evaluate.ReadPinnable(ctx, w.mirror.FlakeRef(sha))
	if err != nil {
		slog.Info("no pinnable packages", "commit", sha, "error", err)
		return
	}
	if _, err := w.db.Exec(ctx, `UPDATE packages SET pinnable = attr = ANY($1)`, pinnable); err != nil {
		slog.Error("store pinnable packages", "error", err)
		return
	}
	w.hub.Publish(realtime.PackageChanged, map[string]string{})
}
