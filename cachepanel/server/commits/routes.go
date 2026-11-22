package commits

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/database"
	"cachepanel/rest"
)

const (
	defaultPage = 50
	maxPage     = 500
)

var errNotRetryable = rest.Conflict("not_retryable", "Bare den nyeste, feilede commiten kan evalueres på nytt")

// Commits lists evaluated revisions.
type Commits struct {
	db   *pgxpool.Pool
	poke func()
}

func New(db *pgxpool.Pool, poke func()) *Commits {
	return &Commits{db: db, poke: poke}
}

func (c *Commits) Mount(r chi.Router) {
	r.Get("/commits", rest.Handle(c.list))
	r.Post("/commits/{sha}/retry", rest.Handle(c.retry))
}

// list pages by position, newest first.
func (c *Commits) list(w http.ResponseWriter, r *http.Request) error {
	query := r.URL.Query()
	before, err := strconv.ParseInt(query.Get("before"), 10, 64)
	if err != nil {
		before = 1 << 62
	}
	limit, err := strconv.Atoi(query.Get("limit"))
	if err != nil || limit <= 0 {
		limit = defaultPage
	}
	body, err := database.JSON(r.Context(), c.db, `
		SELECT json_build_object('items', coalesce(json_agg(row_to_json(c) ORDER BY c.position DESC), '[]'),
			'next', CASE WHEN count(*) = $2 THEN min(c.position) END)
		FROM (
			SELECT sha, position, subject, author, committed_at AS "committedAt", eval_state AS "evalState",
				eval_started_at AS "evalStartedAt", eval_finished_at AS "evalFinishedAt", eval_error AS "evalError",
				attrs, failed_attrs AS "failedAttrs", changed,
				(SELECT coalesce(json_agg(t.name ORDER BY t.name), '[]') FROM profiles t WHERE t.published_rev = commits.sha) AS "publishedFor"
			FROM commits WHERE position < $1 ORDER BY position DESC LIMIT $2) c`, before, min(limit, maxPage))
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (c *Commits) retry(w http.ResponseWriter, r *http.Request) error {
	tag, err := c.db.Exec(r.Context(), `
		DELETE FROM commits WHERE sha = $1 AND eval_state = 'failed'
			AND position = (SELECT max(position) FROM commits)`, chi.URLParam(r, "sha"))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errNotRetryable
	}
	c.poke()
	return rest.NoContent(w)
}
