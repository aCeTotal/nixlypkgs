package packages

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/builds"
	"cachepanel/database"
	"cachepanel/realtime"
	"cachepanel/rest"
)

var errNotCached = rest.Conflict("not_cached", "Only cached versions can be selected")

// Packages exposes cached attributes.
type Packages struct {
	db      *pgxpool.Pool
	hub     *realtime.Hub
	pool    *builds.Pool
	changed func()
}

func New(db *pgxpool.Pool, hub *realtime.Hub, pool *builds.Pool, changed func()) *Packages {
	return &Packages{db: db, hub: hub, pool: pool, changed: changed}
}

func (p *Packages) Mount(r chi.Router) {
	r.Get("/packages", rest.Handle(p.list))
	r.Get("/packages/{attr}", rest.Handle(p.get))
	r.Put("/packages/{attr}/auto", rest.Handle(p.setAuto))
	r.Put("/packages/{attr}/selection", rest.Handle(p.selectVersion))
	r.Post("/versions/{id}/build", p.versionAction(p.pool.Queue))
	r.Post("/versions/{id}/cancel", p.versionAction(p.pool.Cancel))
	r.Delete("/versions/{id}/cache", p.versionAction(p.pool.Drop))
	r.Get("/versions/{id}/log", rest.Handle(p.log))
}

func (p *Packages) list(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), p.db, `
		SELECT coalesce(json_agg(row_to_json(p) ORDER BY p.attr), '[]') FROM (
			SELECT pk.attr, pk.auto_build AS "autoBuild", pk.present, pk.pinnable, pk.eval_error AS "evalError",
				pk.expected_seconds AS "expectedSeconds", pk.selected_version_id AS "selectedVersionId",
				pk.stable_version_id AS "stableVersionId",
				coalesce((SELECT json_agg(json_build_object('id', v.id, 'name', v.name, 'state', v.state,
					'commit', v.last_sha, 'closureBytes', v.closure_bytes) ORDER BY v.last_position DESC)
					FROM versions v WHERE v.package_id = pk.id), '[]') AS versions
			FROM packages pk) p`)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (p *Packages) get(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), p.db, `
		SELECT json_build_object('attr', pk.attr, 'autoBuild', pk.auto_build, 'present', pk.present,
			'pinnable', pk.pinnable, 'evalError', pk.eval_error, 'expectedSeconds', pk.expected_seconds,
			'selectedVersionId', pk.selected_version_id, 'stableVersionId', pk.stable_version_id,
			'versions', coalesce((SELECT json_agg(json_build_object(
				'id', v.id, 'name', v.name, 'drvPath', v.drv_path, 'outputs', v.outputs, 'state', v.state,
				'queuedAt', v.queued_at, 'startedAt', v.started_at, 'finishedAt', v.finished_at,
				'closureBytes', v.closure_bytes, 'error', v.error,
				'first', json_build_object('sha', fc.sha, 'subject', fc.subject, 'author', fc.author, 'time', fc.committed_at),
				'last', json_build_object('sha', lc.sha, 'subject', lc.subject, 'author', lc.author, 'time', lc.committed_at))
				ORDER BY v.last_position DESC)
				FROM versions v JOIN commits fc ON fc.sha = v.first_sha JOIN commits lc ON lc.sha = v.last_sha
				WHERE v.package_id = pk.id), '[]'))
		FROM packages pk WHERE pk.attr = $1`, chi.URLParam(r, "attr"))
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

// setAuto queues or parks unbuilt versions.
func (p *Packages) setAuto(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	attr := chi.URLParam(r, "attr")
	err := pgx.BeginFunc(r.Context(), p.db, func(tx pgx.Tx) error {
		var id int64
		if err := tx.QueryRow(r.Context(), `UPDATE packages SET auto_build = $2 WHERE attr = $1 RETURNING id`, attr, req.Enabled).Scan(&id); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(), `
			UPDATE versions SET state = CASE WHEN $2 THEN 'queued'::build_state ELSE 'pending'::build_state END,
				queued_at = CASE WHEN $2 THEN now() END
			WHERE package_id = $1 AND state = CASE WHEN $2 THEN 'pending'::build_state ELSE 'queued'::build_state END`, id, req.Enabled)
		return err
	})
	if err != nil {
		return err
	}
	p.pool.Wake()
	p.announce(attr)
	return rest.NoContent(w)
}

// selectVersion pins a cached version.
func (p *Packages) selectVersion(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		VersionID *int64 `json:"versionId"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	attr := chi.URLParam(r, "attr")
	tag, err := p.db.Exec(r.Context(), `
		UPDATE packages p SET selected_version_id = $2
		WHERE attr = $1 AND ($2::bigint IS NULL OR EXISTS (
			SELECT 1 FROM versions v WHERE v.id = $2 AND v.package_id = p.id AND v.state = 'cached'))`, attr, req.VersionID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errNotCached
	}
	p.announce(attr)
	return rest.NoContent(w)
}

func (p *Packages) versionAction(action func(context.Context, int64) error) http.HandlerFunc {
	return rest.Handle(func(w http.ResponseWriter, r *http.Request) error {
		id, err := rest.ID(r, "id")
		if err != nil {
			return err
		}
		if err := action(r.Context(), id); err != nil {
			return err
		}
		return rest.NoContent(w)
	})
}

func (p *Packages) log(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	tail, err := p.pool.LogTail(id)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"log": string(tail)})
}

func (p *Packages) announce(attr string) {
	p.hub.Publish(realtime.PackageChanged, map[string]string{"attr": attr})
	p.changed()
}
