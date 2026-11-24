package profiles

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"slices"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/database"
	"cachepanel/modules"
	"cachepanel/realtime"
	"cachepanel/rest"
)

func (b *Rebuilder) Mount(r chi.Router) {
	r.Get("/profiles", rest.Handle(b.list))
	r.Post("/profiles", rest.Handle(b.create))
	r.Get("/profiles/{name}", rest.Handle(b.get))
	r.Put("/profiles/{name}", rest.Handle(b.update))
	r.Delete("/profiles/{name}", rest.Handle(b.remove))
	r.Post("/profiles/{name}/clone", rest.Handle(b.clone))
	r.Post("/profiles/{name}/check", rest.Handle(b.recheck))
	r.Get("/approval", rest.Handle(b.pending))
	r.Post("/approval", rest.Handle(b.approve))
	r.Get("/kernels", rest.Handle(b.kernels))
}

const summary = `
	p.id, p.name, p.title, p.description, p.platform, p.kernel, p.kernel_settings AS "kernelSettings", p.pinned_sha AS "pinnedSha",
	cardinality(p.packages) AS "packageCount",
	(SELECT count(*) FROM profile_modules pm WHERE pm.profile_id = p.id AND pm.slug = ANY($1::text[])) + $2::int AS "moduleCount",
	p.candidate_tree AS "candidateTree", p.candidate_rev AS "candidateRev",
	p.testing_tree AS "testingTree", p.testing_rev AS "testingRev", p.testing_at AS "testingAt",
	p.stable_tree AS "stableTree", p.stable_rev AS "stableRev", p.stable_at AS "stableAt",
	p.check_state AS "checkState", p.check_error AS "checkError", p.checked_at AS "checkedAt", p.updated_at AS "updatedAt"`

func (b *Rebuilder) list(w http.ResponseWriter, r *http.Request) error {
	entries, err := b.moduleCatalogue(r.Context())
	if err != nil {
		return err
	}
	optional := modules.Optional(entries)
	body, err := database.JSON(r.Context(), b.DB, `
		SELECT coalesce(json_agg(row_to_json(p) ORDER BY p.id), '[]') FROM (SELECT `+summary+` FROM profiles p) p`,
		optional, len(entries)-len(optional))
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

// ProfileModule is a catalogue module and whether the profile imports it.
type ProfileModule struct {
	modules.Entry
	Selected bool `json:"selected"`
}

func (b *Rebuilder) get(w http.ResponseWriter, r *http.Request) error {
	entries, err := b.moduleCatalogue(r.Context())
	if err != nil {
		return err
	}
	optional := modules.Optional(entries)
	var detail struct {
		Profile map[string]any  `json:"profile"`
		Modules []ProfileModule `json:"modules"`
		Pkgs    []string        `json:"packages"`
		Files   []File          `json:"files"`
	}
	var chosen []string
	var archive []byte
	err = b.DB.QueryRow(r.Context(), `
		SELECT row_to_json(s), p.packages,
			coalesce((SELECT array_agg(pm.slug) FROM profile_modules pm WHERE pm.profile_id = p.id), '{}'),
			tr.archive
		FROM profiles p
			JOIN LATERAL (SELECT `+summary+`) s ON true
			LEFT JOIN trees tr ON tr.hash = p.candidate_tree
		WHERE p.name = $3`, optional, len(entries)-len(optional), chi.URLParam(r, "name")).
		Scan(&detail.Profile, &detail.Pkgs, &chosen, &archive)
	if err != nil {
		return err
	}
	detail.Modules = make([]ProfileModule, len(entries))
	for i, entry := range entries {
		detail.Modules[i] = ProfileModule{Entry: entry, Selected: entry.Required || slices.Contains(chosen, entry.Slug)}
	}
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
