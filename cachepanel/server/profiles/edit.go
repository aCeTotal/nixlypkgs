package profiles

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"regexp"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/realtime"
	"cachepanel/rest"
)

var (
	namePattern  = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)
	attrPattern  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*(\.[A-Za-z_][A-Za-z0-9_'-]*)*$`)
	platforms    = map[string]bool{"desktop": true, "htpc": true}
	errName      = rest.Unprocessable("invalid_name", "ID kan bare ha små bokstaver, tall og bindestrek (maks 32)")
	errTitle     = rest.Unprocessable("invalid_title", "Navnet må ha 1–80 tegn")
	errPlatform  = rest.Unprocessable("invalid_platform", "Ukjent plattform")
	errPackage   = rest.Unprocessable("invalid_package", "Ugyldig pakke – bruk f.eks. blender eller python3Packages.numpy")
	errPinnedRev = rest.Unprocessable("invalid_revision", "Revisjonen er ikke evaluert")
)

// Selectable modules in catalog order; required always included.
const catalogFor = `coalesce((SELECT array_agg(c.name ORDER BY c.position) FROM catalog_modules c
	WHERE c.present AND NOT c.automatic AND (c.required OR %s)), '{}')`

type identity struct {
	Name        string `json:"name"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Platform    string `json:"platform"`
}

func (i identity) validate() error {
	switch {
	case !namePattern.MatchString(i.Name):
		return errName
	case len(i.Title) == 0 || len([]rune(i.Title)) > 80:
		return errTitle
	case !platforms[i.Platform]:
		return errPlatform
	}
	return nil
}

func (b *Rebuilder) create(w http.ResponseWriter, r *http.Request) error {
	var req identity
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.validate(); err != nil {
		return err
	}
	if _, err := b.db.Exec(r.Context(), `
		INSERT INTO profiles (name, title, description, platform, catalog)
		VALUES ($1, $2, $3, $4, `+fmt.Sprintf(catalogFor, `$4::text = ANY(c.defaults)`)+`)`,
		req.Name, req.Title, req.Description, req.Platform); err != nil {
		return err
	}
	b.changed(req.Name)
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"name": req.Name})
}

type settings struct {
	identity
	Pinned   *string  `json:"pinnedSha"`
	Catalog  []string `json:"catalog"`
	Modules  []int64  `json:"modules"`
	Packages []string `json:"packages"`
}

func (s settings) validate() error {
	if err := s.identity.validate(); err != nil {
		return err
	}
	for _, pkg := range s.Packages {
		if !attrPattern.MatchString(pkg) {
			return errPackage
		}
	}
	return nil
}

func (b *Rebuilder) update(w http.ResponseWriter, r *http.Request) error {
	var req settings
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.validate(); err != nil {
		return err
	}
	err := pgx.BeginFunc(r.Context(), b.db, func(tx pgx.Tx) error {
		return save(r.Context(), tx, chi.URLParam(r, "name"), req)
	})
	if err != nil {
		return err
	}
	b.changed(req.Name)
	return rest.NoContent(w)
}

func save(ctx context.Context, tx pgx.Tx, current string, req settings) error {
	if req.Pinned != nil {
		var done bool
		err := tx.QueryRow(ctx, `SELECT eval_state = 'done' FROM commits WHERE sha = $1`, *req.Pinned).Scan(&done)
		if err != nil || !done {
			return errPinnedRev
		}
	}
	var id int64
	err := tx.QueryRow(ctx, `
		UPDATE profiles SET name = $2, title = $3, description = $4, platform = $5, pinned_sha = $6,
			catalog = `+fmt.Sprintf(catalogFor, `c.name = ANY($7)`)+`, packages = $8, updated_at = now()
		WHERE name = $1 RETURNING id`,
		current, req.Name, req.Title, req.Description, req.Platform, req.Pinned, req.Catalog, uniq(req.Packages)).Scan(&id)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM profile_modules WHERE profile_id = $1 AND module_id <> ALL($2)`, id, req.Modules); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO profile_modules (profile_id, module_id) SELECT $1, unnest($2::bigint[]) ON CONFLICT DO NOTHING`, id, req.Modules)
	return err
}

func (b *Rebuilder) clone(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Name  string `json:"name"`
		Title string `json:"title"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := (identity{Name: req.Name, Title: req.Title, Platform: "desktop"}).validate(); err != nil {
		return err
	}
	err := pgx.BeginFunc(r.Context(), b.db, func(tx pgx.Tx) error {
		var id int64
		err := tx.QueryRow(r.Context(), `
			INSERT INTO profiles (name, title, description, platform, pinned_sha, catalog, packages)
			SELECT $2, $3, description, platform, pinned_sha, catalog, packages FROM profiles WHERE name = $1
			RETURNING id`, chi.URLParam(r, "name"), req.Name, req.Title).Scan(&id)
		if err != nil {
			return err
		}
		_, err = tx.Exec(r.Context(), `
			INSERT INTO profile_modules (profile_id, module_id)
			SELECT $1, module_id FROM profile_modules WHERE profile_id = (SELECT id FROM profiles WHERE name = $2)`,
			id, chi.URLParam(r, "name"))
		return err
	})
	if err != nil {
		return err
	}
	b.changed(req.Name)
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"name": req.Name})
}

func (b *Rebuilder) remove(w http.ResponseWriter, r *http.Request) error {
	var id int64
	if err := b.db.QueryRow(r.Context(), `DELETE FROM profiles WHERE name = $1 RETURNING id`, chi.URLParam(r, "name")).Scan(&id); err != nil {
		return err
	}
	if err := os.RemoveAll(b.systemRoots(id)); err != nil {
		return err
	}
	b.changed(chi.URLParam(r, "name"))
	b.published()
	return rest.NoContent(w)
}

func (b *Rebuilder) changed(name string) {
	b.hub.Publish(realtime.ProfileChanged, map[string]string{"name": name})
	b.Trigger()
}

// uniq keeps first occurrences.
func uniq(values []string) []string {
	seen := map[string]bool{}
	kept := []string{}
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			kept = append(kept, value)
		}
	}
	return kept
}
