package modules

import (
	"context"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/realtime"
	"cachepanel/rest"
	"cachepanel/source"
)

var (
	slugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)
	errSlug     = rest.Unprocessable("invalid_slug", "The file name may only contain lowercase letters, digits and hyphens")
	errTitle    = rest.Unprocessable("invalid_title", "The title needs 1–120 characters")
	errRequired = rest.Conflict("required", "Required modules cannot be deleted")
	errUsed     = rest.Conflict("in_use", "Profiles still choose this module")
	errExists   = rest.Conflict("module_exists", "A module already has that file name")
)

// Modules are the source's NixOS modules.
type Modules struct {
	DB   *pgxpool.Pool
	Hub  *realtime.Hub
	Repo *source.Repo
	// Poke starts evaluating a new commit.
	Poke func()
	// Used checks profile imports at rev.
	Used func(ctx context.Context, rev, slug string) (bool, error)
}

func (m *Modules) Mount(r chi.Router) {
	r.Get("/modules", rest.Handle(m.list))
	r.Post("/modules", rest.Handle(m.create))
	r.Post("/modules/validate", rest.Handle(m.validate))
	r.Get("/modules/{slug}", rest.Handle(m.get))
	r.Put("/modules/{slug}", rest.Handle(m.update))
	r.Delete("/modules/{slug}", rest.Handle(m.remove))
	r.Get("/modules/{slug}/revisions/{sha}", rest.Handle(m.revision))
}

// User is an importing profile.
type User struct {
	Name       string `json:"name"`
	Title      string `json:"title"`
	CheckState string `json:"checkState"`
}

// Summary is a listed module.
type Summary struct {
	Entry
	Position  int        `json:"position"`
	Lines     int        `json:"lines"`
	ChangedAt *time.Time `json:"changedAt"`
	UsedBy    []User     `json:"usedBy"`
}

type profileUse struct {
	User
	Chosen []string
}

// uses lists profiles' chosen modules.
func (m *Modules) uses(ctx context.Context) ([]profileUse, error) {
	rows, err := m.DB.Query(ctx, `
		SELECT p.name, p.title, p.check_state::text, coalesce(array_agg(pm.slug) FILTER (WHERE pm.slug IS NOT NULL), '{}')
		FROM profiles p LEFT JOIN profile_modules pm ON pm.profile_id = p.id
		GROUP BY p.id ORDER BY p.id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (profileUse, error) {
		var use profileUse
		err := row.Scan(&use.Name, &use.Title, &use.CheckState, &use.Chosen)
		return use, err
	})
}

func usedBy(entry Entry, uses []profileUse) []User {
	users := []User{}
	for _, use := range uses {
		if entry.Required || slices.Contains(use.Chosen, entry.Slug) {
			users = append(users, use.User)
		}
	}
	return users
}

func (m *Modules) list(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	head, err := m.Repo.Head(ctx)
	if err != nil {
		return err
	}
	entries, err := Catalogue(ctx, m.Repo, head)
	if err != nil {
		return err
	}
	paths := make([]string, len(entries))
	for i, entry := range entries {
		paths[i] = entry.Path()
	}
	sources, err := m.Repo.FilesAt(ctx, head, paths)
	if err != nil {
		return err
	}
	changed, err := m.Repo.LastChanged(ctx, paths)
	if err != nil {
		return err
	}
	uses, err := m.uses(ctx)
	if err != nil {
		return err
	}
	summaries := make([]Summary, len(entries))
	for i, entry := range entries {
		summaries[i] = Summary{Entry: entry, Position: i + 1, Lines: strings.Count(sources[entry.Path()], "\n"), UsedBy: usedBy(entry, uses)}
		if when, found := changed[entry.Path()]; found {
			summaries[i].ChangedAt = &when
		}
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{"head": head, "modules": summaries})
}

// Detail is a module with history.
type Detail struct {
	Summary
	Head    string          `json:"head"`
	Source  string          `json:"source"`
	History []source.Commit `json:"history"`
}

func (m *Modules) get(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	head, err := m.Repo.Head(ctx)
	if err != nil {
		return err
	}
	entries, err := Catalogue(ctx, m.Repo, head)
	if err != nil {
		return err
	}
	index := find(entries, chi.URLParam(r, "slug"))
	if index < 0 {
		return rest.NotFound()
	}
	entry := entries[index]
	blob, err := m.Repo.FileAt(ctx, head, entry.Path())
	if err != nil {
		return err
	}
	history, err := m.Repo.Log(ctx, entry.Path(), 0)
	if err != nil {
		return err
	}
	uses, err := m.uses(ctx)
	if err != nil {
		return err
	}
	detail := Detail{Head: head, Source: blob.Text, History: history.Commits}
	detail.Summary = Summary{Entry: entry, Position: index + 1, Lines: strings.Count(blob.Text, "\n"), UsedBy: usedBy(entry, uses)}
	if len(history.Commits) > 0 {
		detail.ChangedAt = &history.Commits[0].Time
	}
	return rest.WriteJSON(w, http.StatusOK, detail)
}

func (m *Modules) revision(w http.ResponseWriter, r *http.Request) error {
	entry := Entry{Slug: chi.URLParam(r, "slug")}
	blob, err := m.Repo.FileAt(r.Context(), chi.URLParam(r, "sha"), entry.Path())
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"source": blob.Text})
}

// draft is a module change.
type draft struct {
	Entry
	Base    string `json:"base"`
	Message string `json:"message"`
	Source  string `json:"source"`
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
	entries, err := Catalogue(r.Context(), m.Repo, req.Base)
	if err != nil {
		return err
	}
	if find(entries, req.Slug) >= 0 {
		return errExists
	}
	change, err := moduleEdit(req, append(entries, req.Entry))
	if err != nil {
		return err
	}
	return m.committed(w, r, change)
}

func (m *Modules) update(w http.ResponseWriter, r *http.Request) error {
	var req draft
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	req.Slug = chi.URLParam(r, "slug")
	if err := req.validate(r.Context()); err != nil {
		return err
	}
	entries, err := Catalogue(r.Context(), m.Repo, req.Base)
	if err != nil {
		return err
	}
	index := find(entries, req.Slug)
	if index < 0 {
		return rest.NotFound()
	}
	entries[index] = req.Entry
	change, err := moduleEdit(req, entries)
	if err != nil {
		return err
	}
	return m.committed(w, r, change)
}

// remove keeps modules still used.
func (m *Modules) remove(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	var req struct {
		Base    string `json:"base"`
		Message string `json:"message"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	entries, err := Catalogue(ctx, m.Repo, req.Base)
	if err != nil {
		return err
	}
	index := find(entries, chi.URLParam(r, "slug"))
	if index < 0 {
		return rest.NotFound()
	}
	entry := entries[index]
	if entry.Required {
		return errRequired
	}
	used, err := m.Used(ctx, req.Base, entry.Slug)
	if err != nil {
		return err
	}
	if used {
		return errUsed
	}
	catalogue, err := encode(slices.Delete(entries, index, index+1))
	if err != nil {
		return err
	}
	edit := source.Edit{Base: req.Base, Message: req.Message, Changes: []source.FileChange{
		{Path: entry.Path()},
		{Path: catalogueFile, Content: &catalogue},
	}}
	return m.committed(w, r, edit)
}

// moduleEdit writes module and catalogue.
func moduleEdit(req draft, entries []Entry) (source.Edit, error) {
	catalogue, err := encode(entries)
	return source.Edit{Base: req.Base, Message: req.Message, Changes: []source.FileChange{
		{Path: req.Path(), Content: &req.Source},
		{Path: catalogueFile, Content: &catalogue},
	}}, err
}

func (m *Modules) committed(w http.ResponseWriter, r *http.Request, edit source.Edit) error {
	sha, err := m.Repo.Commit(r.Context(), edit, m.Repo.Author(r))
	if err != nil {
		return err
	}
	m.Poke()
	m.Hub.Publish(realtime.ModuleChanged, map[string]string{"sha": sha})
	m.Hub.Publish(realtime.SourceChanged, map[string]string{"sha": sha})
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"sha": sha})
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
