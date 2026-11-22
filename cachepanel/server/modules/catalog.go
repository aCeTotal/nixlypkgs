package modules

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"cachepanel/database"
	"cachepanel/rest"
)

// catalog lists repository modules by category.
func (m *Modules) catalog(w http.ResponseWriter, r *http.Request) error {
	body, err := database.JSON(r.Context(), m.db, `
		SELECT json_build_object(
			'categories', coalesce((SELECT json_agg(json_build_object('name', name, 'title', title) ORDER BY position)
				FROM catalog_categories), '[]'),
			'modules', coalesce((SELECT json_agg(json_build_object('name', c.name, 'category', c.category, 'title', c.title,
				'path', c.path, 'x86Only', c.x86_only, 'required', c.required, 'automatic', c.automatic, 'present', c.present,
				'usedBy', coalesce((SELECT json_agg(p.name ORDER BY p.name) FROM profiles p WHERE c.name = ANY(p.catalog)), '[]'))
				ORDER BY c.position) FROM catalog_modules c), '[]'))`)
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, body)
}

// catalogSource shows module source.
func (m *Modules) catalogSource(w http.ResponseWriter, r *http.Request) error {
	var path, sha string
	err := m.db.QueryRow(r.Context(), `
		SELECT c.path, (SELECT sha FROM commits WHERE eval_state = 'done' ORDER BY position DESC LIMIT 1)
		FROM catalog_modules c WHERE c.name = $1`, chi.URLParam(r, "name")).Scan(&path, &sha)
	if err != nil {
		return err
	}
	source, err := m.mirror.Show(r.Context(), sha, path)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"source": source, "path": path, "commit": sha})
}
