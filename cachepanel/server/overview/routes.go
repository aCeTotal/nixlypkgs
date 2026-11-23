package overview

import (
	"encoding/json"
	"errors"
	"net/http"
	"syscall"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/builds"
	"cachepanel/database"
	"cachepanel/rest"
	"cachepanel/versions"
	"cachepanel/watcher"
)

// Overview is one dashboard request.
type Overview struct {
	db       *pgxpool.Pool
	watcher  *watcher.Watcher
	pool     *builds.Pool
	cacheDir string
}

func New(db *pgxpool.Pool, w *watcher.Watcher, pool *builds.Pool, cacheDir string) *Overview {
	return &Overview{db: db, watcher: w, pool: pool, cacheDir: cacheDir}
}

func (o *Overview) Mount(r chi.Router) {
	r.Get("/overview", rest.Handle(o.get))
}

type disk struct {
	Total uint64 `json:"total"`
	Free  uint64 `json:"free"`
}

func (o *Overview) get(w http.ResponseWriter, r *http.Request) error {
	cache, err := database.JSON(r.Context(), o.db, `
		SELECT json_build_object(
			'packages', (SELECT count(*) FROM packages WHERE present),
			'states', coalesce((SELECT json_object_agg(state, total) FROM (SELECT state, count(*) AS total FROM versions GROUP BY state) s), '{}'),
			'closureBytes', coalesce((SELECT sum(closure_bytes) FROM versions WHERE state = 'cached'), 0),
			'queue', coalesce((SELECT json_agg(q) FROM (
				SELECT v.id, p.attr, v.name, v.last_sha AS commit, v.priority FROM versions v JOIN packages p ON p.id = v.package_id
				WHERE v.state = 'queued' ORDER BY v.priority DESC, v.last_position DESC, v.id LIMIT 10) q), '[]'),
			'recent', coalesce((SELECT json_agg(f) FROM (
				SELECT v.id, p.attr, v.name, v.state, v.finished_at AS "finishedAt",
					extract(epoch FROM v.finished_at - v.started_at)::int AS seconds
				FROM versions v JOIN packages p ON p.id = v.package_id
				WHERE v.finished_at IS NOT NULL ORDER BY v.finished_at DESC LIMIT 12) f), '[]'))`)
	if err != nil {
		return err
	}
	var stat syscall.Statfs_t
	if err := syscall.Statfs(o.cacheDir, &stat); err != nil {
		return err
	}
	if stat.Bsize <= 0 {
		return errors.New("statfs: invalid block size")
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{
		"cache":   json.RawMessage(cache),
		"watcher": o.watcher.Status(),
		"builds":  o.pool.Snapshot(),
		"disk":    disk{Total: stat.Blocks * uint64(stat.Bsize), Free: stat.Bavail * uint64(stat.Bsize)},
		"keep":    versions.Keep,
	})
}
