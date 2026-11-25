package profiles

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"maps"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/modules"
	"cachepanel/realtime"
	"cachepanel/rest"
)

func (b *Rebuilder) Mount(r chi.Router) {
	r.Post("/profiles/{name}/check", rest.Handle(b.recheck))
	r.Get("/approval", rest.Handle(b.pending))
	r.Post("/approval", rest.Handle(b.approve))
	r.Get("/kernels", rest.Handle(b.kernels))
}

func (p *Routes) Mount(r chi.Router) {
	r.Get("/profiles", rest.Handle(p.list))
	r.Post("/profiles", rest.Handle(p.create))
	r.Get("/profiles/{name}", rest.Handle(p.get))
	r.Put("/profiles/{name}", rest.Handle(p.update))
	r.Delete("/profiles/{name}", rest.Handle(p.remove))
	r.Post("/profiles/{name}/clone", rest.Handle(p.clone))
}

// progress is a profile's rollout.
type progress struct {
	ID            *int64     `json:"id"`
	CandidateTree *string    `json:"candidateTree"`
	CandidateRev  *string    `json:"candidateRev"`
	TestingTree   *string    `json:"testingTree"`
	TestingRev    *string    `json:"testingRev"`
	TestingAt     *time.Time `json:"testingAt"`
	StableTree    *string    `json:"stableTree"`
	StableRev     *string    `json:"stableRev"`
	StableAt      *time.Time `json:"stableAt"`
	CheckState    string     `json:"checkState"`
	CheckError    *string    `json:"checkError"`
	CheckedAt     *time.Time `json:"checkedAt"`
	// Cache holdings per branch.
	TestingPaths *int   `json:"testingPaths"`
	TestingBytes *int64 `json:"testingBytes"`
	StablePaths  *int   `json:"stablePaths"`
	StableBytes  *int64 `json:"stableBytes"`
}

const progressColumns = `p.name, p.id, p.candidate_tree, p.candidate_rev, p.testing_tree, p.testing_rev, p.testing_at,
	p.stable_tree, p.stable_rev, p.stable_at, p.check_state::text, p.check_error, p.checked_at,
	p.testing_paths, p.testing_bytes, p.stable_paths, p.stable_bytes`

func (s *progress) fields(name *string) []any {
	return []any{name, &s.ID, &s.CandidateTree, &s.CandidateRev, &s.TestingTree, &s.TestingRev, &s.TestingAt,
		&s.StableTree, &s.StableRev, &s.StableAt, &s.CheckState, &s.CheckError, &s.CheckedAt,
		&s.TestingPaths, &s.TestingBytes, &s.StablePaths, &s.StableBytes}
}

// Summary is a profile with progress.
type Summary struct {
	Name string `json:"name"`
	Profile
	PackageCount int `json:"packageCount"`
	ModuleCount  int `json:"moduleCount"`
	progress
}

// Untracked profiles await testing.
func summarize(name string, profile Profile, tracked progress, required int) Summary {
	if tracked.CheckState == "" {
		tracked.CheckState = "pending"
	}
	return Summary{Name: name, Profile: profile, PackageCount: len(profile.Packages),
		ModuleCount: required + len(profile.Modules), progress: tracked}
}

func (p *Routes) list(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	head, err := p.Source.Head(ctx)
	if err != nil {
		return err
	}
	kept, err := profilesAt(ctx, p.Source, head)
	if err != nil {
		return err
	}
	entries, err := modules.Catalogue(ctx, p.Source, head)
	if err != nil {
		return err
	}
	rows, err := p.DB.Query(ctx, `SELECT `+progressColumns+` FROM profiles p`)
	if err != nil {
		return err
	}
	tracked := map[string]progress{}
	var name string
	var next progress
	if _, err := pgx.ForEachRow(rows, next.fields(&name), func() error {
		tracked[name] = next
		return nil
	}); err != nil {
		return err
	}
	required := len(entries) - len(modules.Optional(entries))
	summaries := make([]Summary, 0, len(kept))
	for _, name := range slices.Sorted(maps.Keys(kept)) {
		summaries = append(summaries, summarize(name, kept[name], tracked[name], required))
	}
	return rest.WriteJSON(w, http.StatusOK, summaries)
}

// ProfileModule is a module choice.
type ProfileModule struct {
	modules.Entry
	Selected bool `json:"selected"`
}

// Detail is an editable profile.
type Detail struct {
	Profile Summary         `json:"profile"`
	Head    string          `json:"head"`
	Modules []ProfileModule `json:"modules"`
	Files   []File          `json:"files"`
}

func (p *Routes) get(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	name := chi.URLParam(r, "name")
	head, err := p.Source.Head(ctx)
	if err != nil {
		return err
	}
	profile, err := p.profileAt(ctx, head, name)
	if err != nil {
		return err
	}
	entries, err := modules.Catalogue(ctx, p.Source, head)
	if err != nil {
		return err
	}
	var tracked progress
	var archive []byte
	err = p.DB.QueryRow(ctx, `SELECT `+progressColumns+`, tr.archive FROM profiles p LEFT JOIN trees tr ON tr.hash = p.candidate_tree
		WHERE p.name = $1`, name).Scan(append(tracked.fields(new(string)), &archive)...)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	detail := Detail{Head: head, Modules: make([]ProfileModule, len(entries))}
	required := 0
	for i, entry := range entries {
		detail.Modules[i] = ProfileModule{Entry: entry, Selected: entry.Required || slices.Contains(profile.Modules, entry.Slug)}
		if entry.Required {
			required++
		}
	}
	detail.Profile = summarize(name, profile, tracked, required)
	if detail.Files, err = readArchive(archive); err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, detail)
}

// readArchive lists a tree's files.
func readArchive(archive []byte) ([]File, error) {
	files := []File{}
	if archive == nil {
		return files, nil
	}
	compressed, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return nil, err
	}
	reader := tar.NewReader(compressed)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return files, nil
		}
		if err != nil {
			return nil, err
		}
		if header.Typeflag != tar.TypeReg {
			continue
		}
		content, err := io.ReadAll(reader)
		if err != nil {
			return nil, err
		}
		files = append(files, File{Path: strings.TrimPrefix(header.Name, treeRoot), Content: string(content)})
	}
}

func (b *Rebuilder) recheck(w http.ResponseWriter, r *http.Request) error {
	if err := b.mutate(r, `UPDATE profiles SET check_state = 'pending', check_error = NULL WHERE name = $1 AND check_state <> 'running'`); err != nil {
		return err
	}
	b.wakeChecks()
	return rest.NoContent(w)
}

// mutate updates by name.
func (b *Rebuilder) mutate(r *http.Request, query string) error {
	tag, err := b.DB.Exec(r.Context(), query, chi.URLParam(r, "name"))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	b.Hub.Publish(realtime.ProfileChanged, map[string]string{"name": chi.URLParam(r, "name")})
	return nil
}
