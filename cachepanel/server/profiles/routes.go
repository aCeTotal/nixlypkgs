package profiles

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/database"
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
	r.Post("/profiles/{name}/publish", rest.Handle(b.publish))
}

const summary = `
	p.id, p.name, p.title, p.description, p.platform, p.pinned_sha AS "pinnedSha",
	cardinality(p.packages) AS "packageCount",
	(SELECT count(*) FROM modules m WHERE m.required
		OR EXISTS (SELECT 1 FROM profile_modules pm WHERE pm.profile_id = p.id AND pm.module_id = m.id)) AS "moduleCount",
	p.candidate_tree AS "candidateTree", p.candidate_rev AS "candidateRev",
	p.published_tree AS "publishedTree", p.published_rev AS "publishedRev", p.published_at AS "publishedAt",
	p.check_state AS "checkState", p.check_error AS "checkError", p.checked_at AS "checkedAt", p.updated_at AS "updatedAt"`

func (b *Rebuilder) list(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), b.db, `
		SELECT coalesce(json_agg(row_to_json(p) ORDER BY p.id), '[]') FROM (SELECT `+summary+` FROM profiles p) p`)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

func (b *Rebuilder) get(w http.ResponseWriter, r *http.Request) error {
	var detail struct {
		Profile map[string]any `json:"profile"`
		Modules []any          `json:"modules"`
		Pkgs    []string       `json:"packages"`
		Files   []File         `json:"files"`
	}
	var archive []byte
	err := b.db.QueryRow(r.Context(), `
		SELECT row_to_json(s), p.packages,
			coalesce((SELECT json_agg(json_build_object('id', m.id, 'slug', m.slug, 'title', m.title,
				'description', m.description, 'required', m.required,
				'selected', m.required OR EXISTS (SELECT 1 FROM profile_modules pm WHERE pm.profile_id = p.id AND pm.module_id = m.id))
				ORDER BY m.position) FROM modules m), '[]'),
			tr.archive
		FROM profiles p
			JOIN LATERAL (SELECT `+summary+`) s ON true
			LEFT JOIN trees tr ON tr.hash = p.candidate_tree
		WHERE p.name = $1`, chi.URLParam(r, "name")).
		Scan(&detail.Profile, &detail.Pkgs, &detail.Modules, &archive)
	if err != nil {
		return err
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

// publish ships an untested candidate.
func (b *Rebuilder) publish(w http.ResponseWriter, r *http.Request) error {
	if err := b.mutate(r, `
		UPDATE profiles SET published_tree = candidate_tree, published_rev = candidate_rev, published_at = now()
		WHERE name = $1 AND candidate_tree IS NOT NULL AND candidate_rev IS NOT NULL`); err != nil {
		return err
	}
	b.published()
	return rest.NoContent(w)
}

// mutate updates by name.
func (b *Rebuilder) mutate(r *http.Request, query string) error {
	tag, err := b.db.Exec(r.Context(), query, chi.URLParam(r, "name"))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	b.hub.Publish(realtime.ProfileChanged, map[string]string{"name": chi.URLParam(r, "name")})
	return nil
}
