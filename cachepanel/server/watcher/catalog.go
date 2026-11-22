package watcher

import (
	"context"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5"

	"cachepanel/evaluate"
	"cachepanel/realtime"
)

// registry holds unnest() columns.
type registry struct {
	names, categories, titles, paths, defaults []string
	positions                                  []int
	x86, required, automatic                   []bool
}

func columnsOf(modules []evaluate.CatalogModule) registry {
	var r registry
	for position, module := range modules {
		r.names = append(r.names, module.Name)
		r.categories = append(r.categories, module.Category)
		r.titles = append(r.titles, module.Title)
		r.paths = append(r.paths, module.Path)
		r.defaults = append(r.defaults, strings.Join(module.Profiles, ","))
		r.positions = append(r.positions, position)
		r.x86 = append(r.x86, module.X86)
		r.required = append(r.required, module.Required)
		r.automatic = append(r.automatic, module.Automatic)
	}
	return r
}

// syncCatalog stores the head's module registry.
func (w *Watcher) syncCatalog(ctx context.Context, sha string) {
	catalog, err := evaluate.ReadCatalog(ctx, w.mirror.FlakeRef(sha))
	if err != nil {
		slog.Info("no module catalog", "commit", sha, "error", err)
		return
	}
	r := columnsOf(catalog.Modules)
	err = pgx.BeginFunc(ctx, w.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			INSERT INTO catalog_modules (name, category, title, path, defaults, position, x86_only, required, automatic)
			SELECT name, category, title, path, coalesce(string_to_array(nullif(defaults, ''), ','), '{}'), position, x86, required, automatic
			FROM unnest($1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::int[], $7::boolean[], $8::boolean[], $9::boolean[])
				AS t(name, category, title, path, defaults, position, x86, required, automatic)
			ON CONFLICT (name) DO UPDATE SET category = EXCLUDED.category, title = EXCLUDED.title, path = EXCLUDED.path,
				defaults = EXCLUDED.defaults, position = EXCLUDED.position, x86_only = EXCLUDED.x86_only,
				required = EXCLUDED.required, automatic = EXCLUDED.automatic, present = true`,
			r.names, r.categories, r.titles, r.paths, r.defaults, r.positions, r.x86, r.required, r.automatic); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE catalog_modules SET present = false WHERE present AND name <> ALL($1)`, r.names); err != nil {
			return err
		}
		if err := storeCategories(ctx, tx, catalog.Categories); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE packages SET pinnable = attr = ANY($1)`, catalog.Pinnable)
		return err
	})
	if err != nil {
		slog.Error("store module catalog", "error", err)
		return
	}
	w.hub.Publish(realtime.ModuleChanged, map[string]string{})
}

func storeCategories(ctx context.Context, tx pgx.Tx, categories []evaluate.Category) error {
	names := make([]string, len(categories))
	titles := make([]string, len(categories))
	positions := make([]int, len(categories))
	for i, category := range categories {
		names[i], titles[i], positions[i] = category.Name, category.Title, i
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO catalog_categories (name, title, position)
		SELECT * FROM unnest($1::text[], $2::text[], $3::int[])
		ON CONFLICT (name) DO UPDATE SET title = EXCLUDED.title, position = EXCLUDED.position`,
		names, titles, positions); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `DELETE FROM catalog_categories WHERE name <> ALL($1)`, names)
	return err
}
