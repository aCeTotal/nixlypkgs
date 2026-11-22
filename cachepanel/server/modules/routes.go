package modules

import (
	"context"
	"net/http"
	"regexp"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/database"
	"cachepanel/realtime"
	"cachepanel/rest"
)

var (
	slugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)
	errSlug     = rest.Unprocessable("invalid_slug", "Filnavnet kan bare ha små bokstaver, tall og bindestrek")
	errTitle    = rest.Unprocessable("invalid_title", "Tittel må ha 1–120 tegn")
	errRequired = rest.Conflict("required", "Påkrevde moduler kan ikke slettes")
)

// Modules are the NixOS modules profiles import.
type Modules struct {
	db      *pgxpool.Pool
	hub     *realtime.Hub
	changed func()
}

func New(db *pgxpool.Pool, hub *realtime.Hub, changed func()) *Modules {
	return &Modules{db: db, hub: hub, changed: changed}
}

func (m *Modules) Mount(r chi.Router) {
	r.Get("/modules", rest.Handle(m.list))
	r.Post("/modules", rest.Handle(m.create))
	r.Post("/modules/validate", rest.Handle(m.validate))
	r.Get("/modules/{id}", rest.Handle(m.get))
	r.Put("/modules/{id}", rest.Handle(m.update))
	r.Delete("/modules/{id}", rest.Handle(m.remove))
	r.Get("/modules/{id}/revisions/{revision}", rest.Handle(m.revision))
}

// Required modules belong to every profile.
const usedBy = `coalesce((SELECT json_agg(json_build_object('name', p.name, 'title', p.title, 'checkState', p.check_state)
	ORDER BY p.id) FROM profiles p
	WHERE m.required OR EXISTS (SELECT 1 FROM profile_modules pm WHERE pm.profile_id = p.id AND pm.module_id = m.id)), '[]')`

const fields = `'id', m.id, 'slug', m.slug, 'title', m.title, 'description', m.description, 'required', m.required,
	'position', m.position, 'revision', m.revision, 'updatedAt', m.updated_at, 'usedBy', ` + usedBy

func (m *Modules) list(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), m.db, `
		SELECT coalesce(json_agg(json_build_object(`+fields+`,
			'lines', array_length(string_to_array(m.source, E'\n'), 1)) ORDER BY m.position), '[]')
		FROM modules m`)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (m *Modules) get(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	body, err := database.JSON(r.Context(), m.db, `
		SELECT json_build_object(`+fields+`, 'source', m.source,
			'revisions', (SELECT json_agg(json_build_object('revision', rv.revision, 'createdAt', rv.created_at)
				ORDER BY rv.revision DESC) FROM module_revisions rv WHERE rv.module_id = m.id))
		FROM modules m WHERE m.id = $1`, id)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (m *Modules) revision(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	revision, err := rest.ID(r, "revision")
	if err != nil {
		return err
	}
	var source string
	if err := m.db.QueryRow(r.Context(), `SELECT source FROM module_revisions WHERE module_id = $1 AND revision = $2`,
		id, revision).Scan(&source); err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"source": source})
}

type draft struct {
	Slug        string `json:"slug"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Source      string `json:"source"`
	Required    bool   `json:"required"`
}

func (d draft) validate(ctx context.Context) error {
	if !slugPattern.MatchString(d.Slug) {
		return errSlug
	}
	if len(d.Title) == 0 || len([]rune(d.Title)) > 120 {
		return errTitle
	}
	return validSyntax(ctx, d.Source)
}

// create appends to the import order.
func (m *Modules) create(w http.ResponseWriter, r *http.Request) error {
	var req draft
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.validate(r.Context()); err != nil {
		return err
	}
	var id int64
	err := pgx.BeginFunc(r.Context(), m.db, func(tx pgx.Tx) error {
		if err := tx.QueryRow(r.Context(), `
			INSERT INTO modules (slug, title, description, source, required, position)
			VALUES ($1, $2, $3, $4, $5, (SELECT coalesce(max(position), 0) + 1 FROM modules)) RETURNING id`,
			req.Slug, req.Title, req.Description, req.Source, req.Required).Scan(&id); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(), `INSERT INTO module_revisions (module_id, revision, source) VALUES ($1, 1, $2)`, id, req.Source)
		return err
	})
	if err != nil {
		return err
	}
	m.announce(id)
	return rest.WriteJSON(w, http.StatusCreated, map[string]int64{"id": id})
}

// update keeps source revisions.
func (m *Modules) update(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	var req draft
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.validate(r.Context()); err != nil {
		return err
	}
	err = pgx.BeginFunc(r.Context(), m.db, func(tx pgx.Tx) error {
		var revision int
		if err := tx.QueryRow(r.Context(), `
			UPDATE modules SET slug = $2, title = $3, description = $4, required = $6, updated_at = now(),
				revision = revision + (source IS DISTINCT FROM $5)::int, source = $5
			WHERE id = $1 RETURNING revision`,
			id, req.Slug, req.Title, req.Description, req.Source, req.Required).Scan(&revision); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(), `
			INSERT INTO module_revisions (module_id, revision, source) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
			id, revision, req.Source)
		return err
	})
	if err != nil {
		return err
	}
	m.announce(id)
	return rest.NoContent(w)
}

// remove keeps required modules; profiles hold the rest.
func (m *Modules) remove(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	tag, err := m.db.Exec(r.Context(), `DELETE FROM modules WHERE id = $1 AND NOT required`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return m.missingOrRequired(r.Context(), id)
	}
	m.announce(id)
	return rest.NoContent(w)
}

func (m *Modules) missingOrRequired(ctx context.Context, id int64) error {
	var exists bool
	if err := m.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM modules WHERE id = $1)`, id).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return errRequired
	}
	return rest.NotFound()
}

// validate checks syntax while editing.
func (m *Modules) validate(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Source string `json:"source"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	problem, err := parse(r.Context(), req.Source)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, problem)
}

func (m *Modules) announce(id int64) {
	m.hub.Publish(realtime.ModuleChanged, map[string]int64{"id": id})
	m.changed()
}
