package wizard

import (
	"errors"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/database"
	"cachepanel/recipe"
	"cachepanel/rest"
)

var (
	errBusy      = rest.Conflict("recipe_busy", "The recipe is being imported or built")
	errNotTested = rest.Conflict("not_tested", "The recipe must build without errors before it is published")
	errAttrTaken = rest.Conflict("attr_taken", "nixpkgs already has a package with this name; choose another")
)

func (s *Service) Mount(r chi.Router) {
	r.Get("/recipes", rest.Handle(s.list))
	r.Post("/recipes", rest.Handle(s.create))
	r.Get("/recipes/{id}", rest.Handle(s.get))
	r.Put("/recipes/{id}", rest.Handle(s.update))
	r.Delete("/recipes/{id}", rest.Handle(s.remove))
	r.Post("/recipes/{id}/build", rest.Handle(s.build))
	r.Post("/recipes/{id}/stop", rest.Handle(s.stopBuild))
	r.Get("/recipes/{id}/log", rest.Handle(s.log))
	r.Post("/recipes/{id}/publish", rest.Handle(s.publish))
	r.Get("/publishing", rest.Handle(s.publishing))
	r.Post("/sources", rest.Handle(s.upload))
	r.Get("/nixpkgs", rest.Handle(s.search))
}

func (s *Service) list(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), s.db, `
		SELECT coalesce(json_agg(json_build_object(
			'id', id, 'attr', attr, 'state', state, 'error', error, 'origin', origin,
			'pname', spec->>'pname', 'version', spec->>'version', 'builder', spec->>'builder',
			'description', spec->'meta'->>'description', 'publishedSha', published_sha, 'updatedAt', updated_at)
			ORDER BY updated_at DESC), '[]')
		FROM recipes`)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (s *Service) create(w http.ResponseWriter, r *http.Request) error {
	var req Request
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	var id int64
	if err := s.db.QueryRow(r.Context(), `INSERT INTO recipes (origin) VALUES ($1) RETURNING id`, origin(req)).Scan(&id); err != nil {
		return err
	}
	s.start(id, s.importJob(id, req))
	s.changed(id)
	return rest.WriteJSON(w, http.StatusAccepted, map[string]int64{"id": id})
}

type file struct {
	Name string `json:"name"`
	// Text is empty for binary files.
	Text string `json:"text"`
	Size int    `json:"size"`
}

func (s *Service) get(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	var view struct {
		ID           int64          `json:"id"`
		Attr         *string        `json:"attr"`
		State        State          `json:"state"`
		Error        *string        `json:"error"`
		Origin       map[string]any `json:"origin"`
		Spec         *recipe.Spec   `json:"spec"`
		Report       report         `json:"report"`
		Output       *string        `json:"output"`
		PublishedSha *string        `json:"publishedSha"`
		Files        []file         `json:"files"`
	}
	err = s.db.QueryRow(r.Context(), `
		SELECT id, attr, state, error, origin, spec, report, output, published_sha FROM recipes WHERE id = $1`, id).
		Scan(&view.ID, &view.Attr, &view.State, &view.Error, &view.Origin, &view.Spec, &view.Report, &view.Output, &view.PublishedSha)
	if err != nil {
		return err
	}
	view.Files = []file{}
	if view.Spec != nil {
		draft, _, err := s.loadDraft(r.Context(), id)
		if err != nil {
			return err
		}
		files, err := s.files(r.Context(), draft)
		if err != nil {
			return err
		}
		view.Files = describe(files)
	}
	return rest.WriteJSON(w, http.StatusOK, view)
}

func (s *Service) update(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	var req struct {
		Spec  recipe.Spec       `json:"spec"`
		Files map[string]string `json:"files"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.Spec.Validate(); err != nil {
		return rest.Unprocessable("invalid_recipe", err.Error())
	}
	taken, err := s.lab.Taken(r.Context(), req.Spec.Attr)
	if err != nil {
		return err
	}
	if taken {
		return errAttrTaken
	}
	err = pgx.BeginFunc(r.Context(), s.db, func(tx pgx.Tx) error {
		tag, err := tx.Exec(r.Context(), `
			UPDATE recipes SET attr = $2, spec = $3, state = 'draft', error = NULL, updated_at = now()
			WHERE id = $1 AND state NOT IN ('importing', 'building')`, id, req.Spec.Attr, req.Spec)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return errBusy
		}
		return saveTexts(r.Context(), tx, id, req.Files)
	})
	if err != nil {
		return err
	}
	s.changed(id)
	return rest.NoContent(w)
}

func (s *Service) remove(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	s.stop(id)
	if _, err := s.db.Exec(r.Context(), `DELETE FROM recipes WHERE id = $1`, id); err != nil {
		return err
	}
	for _, path := range []string{s.logPath(id), s.rootPath(id)} {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	s.changed(id)
	return rest.NoContent(w)
}

func (s *Service) build(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	tag, err := s.db.Exec(r.Context(), `
		UPDATE recipes SET state = 'building', error = NULL, updated_at = now()
		WHERE id = $1 AND spec IS NOT NULL AND state NOT IN ('importing', 'building')`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errBusy
	}
	s.start(id, s.buildJob(id))
	s.changed(id)
	return rest.NoContent(w)
}

func (s *Service) stopBuild(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	s.stop(id)
	return rest.NoContent(w)
}

func (s *Service) publish(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	var state State
	if err := s.db.QueryRow(r.Context(), `SELECT state FROM recipes WHERE id = $1`, id).Scan(&state); err != nil {
		return err
	}
	if state != Ready && state != Published {
		return errNotTested
	}
	draft, _, err := s.loadDraft(r.Context(), id)
	if err != nil {
		return err
	}
	files, err := s.files(r.Context(), draft)
	if err != nil {
		return err
	}
	sha, err := s.publisher.Publish(r.Context(), draft.Spec.Attr, draft.Spec.Version, files)
	if err != nil {
		return rest.Conflict("publish_failed", err.Error())
	}
	if _, err := s.db.Exec(r.Context(), `
		UPDATE recipes SET state = 'published', published_sha = $2, published_at = now(), updated_at = now() WHERE id = $1`, id, sha); err != nil {
		return err
	}
	s.poke()
	s.changed(id)
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"sha": sha})
}

func (s *Service) search(w http.ResponseWriter, r *http.Request) error {
	found, err := s.lab.Search(r.Context(), r.URL.Query().Get("q"))
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, found)
}

// publishing shows where publishes go and the key to allow.
func (s *Service) publishing(w http.ResponseWriter, r *http.Request) error {
	key, err := s.publisher.PublicKey(r.Context())
	if errors.Is(err, errNoRemote) {
		return rest.WriteJSON(w, http.StatusOK, map[string]any{"remote": nil, "publicKey": nil})
	}
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{"remote": s.publisher.Remote, "publicKey": key})
}
