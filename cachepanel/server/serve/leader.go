package serve

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// Shared by every panel instance.
	leaderLock     = 7_163_201
	leaderInterval = 15 * time.Second
)

// lead runs work once fleet-wide.
func lead(ctx context.Context, db *pgxpool.Pool, work func(context.Context) error) error {
	for ctx.Err() == nil {
		conn, err := db.Acquire(ctx)
		if err != nil {
			sleep(ctx, leaderInterval)
			continue
		}
		var held bool
		err = conn.QueryRow(ctx, `SELECT pg_try_advisory_lock($1)`, leaderLock).Scan(&held)
		if err != nil || !held {
			conn.Release()
			sleep(ctx, leaderInterval)
			continue
		}
		slog.Info("leading background work")
		workCtx, cancel := context.WithCancel(ctx)
		go watchLock(workCtx, cancel, conn)
		err = work(workCtx)
		cancel()
		_, _ = conn.Exec(context.WithoutCancel(ctx), `SELECT pg_advisory_unlock($1)`, leaderLock)
		conn.Release()
		if err != nil {
			return err
		}
	}
	return nil
}

// watchLock stops on lost lock.
func watchLock(ctx context.Context, cancel context.CancelFunc, conn *pgxpool.Conn) {
	ticker := time.NewTicker(leaderInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		if err := conn.Ping(ctx); err != nil && ctx.Err() == nil {
			slog.Warn("lost leader lock", "error", err)
			cancel()
			return
		}
	}
}

func sleep(ctx context.Context, pause time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(pause):
	}
}
