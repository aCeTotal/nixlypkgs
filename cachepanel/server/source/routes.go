package source

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"cachepanel/realtime"
	"cachepanel/rest"
)

// Routes manage who may push.
type Routes struct {
	Repo *Repo
	Keys Keys
	Hub  *realtime.Hub
	// Poke starts evaluating a new commit.
	Poke func()
	// Remote is what pushers add.
	Remote string
}

func (s *Routes) Mount(r chi.Router) {
	r.Get("/source", rest.Handle(s.overview))
	r.Post("/source/keys", rest.Handle(s.add))
	r.Delete("/source/keys/{id}", rest.Handle(s.remove))
	r.Get("/source/tree", rest.Handle(s.tree))
	r.Get("/source/file", rest.Handle(s.file))
	r.Get("/source/log", rest.Handle(s.log))
	r.Get("/source/commits/{sha}", rest.Handle(s.show))
	r.Post("/source/commits", rest.Handle(s.commit))
	r.Post("/source/commits/{sha}/revert", rest.Handle(s.revert))
	r.Get("/source/inputs", rest.Handle(s.inputs))
	r.Post("/source/inputs/update", rest.Handle(s.updateInputs))
}

type overview struct {
	Clone  string `json:"clone"`
	Remote string `json:"remote"`
	Keys   []Key  `json:"keys"`
}

func (s *Routes) overview(w http.ResponseWriter, r *http.Request) error {
	keys, err := s.Keys.List(r.Context())
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, overview{Clone: s.Repo.public, Remote: s.Remote, Keys: keys})
}

type addition struct {
	Name      string `json:"name"`
	PublicKey string `json:"publicKey"`
}

func (s *Routes) add(w http.ResponseWriter, r *http.Request) error {
	var req addition
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	key, err := s.Keys.Add(r.Context(), req.Name, req.PublicKey)
	if err != nil {
		return err
	}
	s.Hub.Publish(realtime.SourceChanged, map[string]int64{"id": key.ID})
	return rest.WriteJSON(w, http.StatusCreated, key)
}

func (s *Routes) remove(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	if err := s.Keys.Remove(r.Context(), id); err != nil {
		return err
	}
	s.Hub.Publish(realtime.SourceChanged, map[string]int64{"id": id})
	return rest.NoContent(w)
}

func (s *Routes) tree(w http.ResponseWriter, r *http.Request) error {
	listing, err := s.Repo.Tree(r.Context(), r.URL.Query().Get("path"))
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, listing)
}

func (s *Routes) file(w http.ResponseWriter, r *http.Request) error {
	blob, err := s.Repo.File(r.Context(), r.URL.Query().Get("path"))
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, blob)
}

func (s *Routes) log(w http.ResponseWriter, r *http.Request) error {
	skip, err := strconv.Atoi(r.URL.Query().Get("skip"))
	if err != nil || skip < 0 {
		skip = 0
	}
	page, err := s.Repo.Log(r.Context(), r.URL.Query().Get("path"), skip)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, page)
}

func (s *Routes) show(w http.ResponseWriter, r *http.Request) error {
	details, err := s.Repo.Show(r.Context(), chi.URLParam(r, "sha"))
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, details)
}

func (s *Routes) commit(w http.ResponseWriter, r *http.Request) error {
	var edit Edit
	if err := rest.Decode(r, &edit); err != nil {
		return err
	}
	sha, err := s.Repo.Commit(r.Context(), edit, s.Repo.Author(r))
	if err != nil {
		return err
	}
	return s.committed(w, sha)
}

func (s *Routes) revert(w http.ResponseWriter, r *http.Request) error {
	undo := Reversal{Commit: chi.URLParam(r, "sha")}
	if err := rest.Decode(r, &undo); err != nil {
		return err
	}
	sha, err := s.Repo.Revert(r.Context(), undo, s.Repo.Author(r))
	if err != nil {
		return err
	}
	return s.committed(w, sha)
}

// committed starts the new commit's evaluation.
func (s *Routes) committed(w http.ResponseWriter, sha string) error {
	s.Poke()
	s.Hub.Publish(realtime.SourceChanged, map[string]string{"sha": sha})
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"sha": sha})
}

func (s *Routes) inputs(w http.ResponseWriter, r *http.Request) error {
	inputs, err := s.Repo.Inputs(r.Context())
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, inputs)
}

func (s *Routes) updateInputs(w http.ResponseWriter, r *http.Request) error {
	var update InputUpdate
	if err := rest.Decode(r, &update); err != nil {
		return err
	}
	sha, err := s.Repo.UpdateInputs(r.Context(), update, s.Repo.Author(r))
	if err != nil {
		return err
	}
	return s.committed(w, sha)
}
