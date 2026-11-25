package profiles

import (
	"context"
	"encoding/json"
	"maps"
	"os"
	"slices"

	"github.com/jackc/pgx/v5"
)

// named is a profile with name.
type named struct {
	Name string `json:"name"`
	Profile
}

const upsertProfiles = `
	INSERT INTO profiles AS p (name, title, description, platform, kernel, kernel_settings, pinned_sha, packages)
	SELECT s.name, s.title, s.description, s.platform::platform, s.kernel, coalesce(s."kernelSettings", '{}'), s."pinnedSha",
		ARRAY(SELECT jsonb_array_elements_text(coalesce(s.packages, '[]')))
	FROM jsonb_to_recordset($1) AS s(name text, title text, description text, platform text, kernel text,
		"kernelSettings" jsonb, "pinnedSha" text, packages jsonb)
	ON CONFLICT (name) DO UPDATE SET title = excluded.title, description = excluded.description,
		platform = excluded.platform, kernel = excluded.kernel, kernel_settings = excluded.kernel_settings,
		pinned_sha = excluded.pinned_sha, packages = excluded.packages, updated_at = now()
	WHERE (p.title, p.description, p.platform, p.kernel, p.kernel_settings, p.pinned_sha, p.packages)
		IS DISTINCT FROM (excluded.title, excluded.description, excluded.platform, excluded.kernel,
			excluded.kernel_settings, excluded.pinned_sha, excluded.packages)`

const chooseModules = `
	WITH chosen AS (
		SELECT p.id, m.slug
		FROM jsonb_to_recordset($1) AS s(name text, modules jsonb)
			JOIN profiles p ON p.name = s.name
			CROSS JOIN jsonb_array_elements_text(coalesce(s.modules, '[]')) AS m(slug)
	), dropped AS (
		DELETE FROM profile_modules pm
		WHERE NOT EXISTS (SELECT 1 FROM chosen c WHERE c.id = pm.profile_id AND c.slug = pm.slug)
		RETURNING 1
	), added AS (
		INSERT INTO profile_modules (profile_id, slug) SELECT id, slug FROM chosen ON CONFLICT DO NOTHING
		RETURNING 1
	)
	SELECT (SELECT count(*) FROM dropped) + (SELECT count(*) FROM added)`

// syncProfiles mirrors testing's profiles.
func (b *Rebuilder) syncProfiles(ctx context.Context, rev string) (bool, error) {
	if rev == "" {
		return false, nil
	}
	profiles, err := profilesAt(ctx, b.Source, rev)
	// Older commits predate source profiles.
	if err != nil || len(profiles) == 0 {
		return false, err
	}
	rows := make([]named, 0, len(profiles))
	for _, name := range slices.Sorted(maps.Keys(profiles)) {
		rows = append(rows, named{Name: name, Profile: profiles[name]})
	}
	encoded, err := json.Marshal(rows)
	if err != nil {
		return false, err
	}
	var removed []int64
	var changed int64
	err = pgx.BeginFunc(ctx, b.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, upsertProfiles, encoded)
		if err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, chooseModules, encoded).Scan(&changed); err != nil {
			return err
		}
		changed += tag.RowsAffected()
		gone, err := tx.Query(ctx, `DELETE FROM profiles WHERE name <> ALL($1::text[]) RETURNING id`, slices.Sorted(maps.Keys(profiles)))
		if err != nil {
			return err
		}
		removed, err = pgx.CollectRows(gone, pgx.RowTo[int64])
		return err
	})
	if err != nil {
		return false, err
	}
	return changed > 0 || len(removed) > 0, b.forget(removed)
}

// forget drops removed profiles' roots.
func (b *Rebuilder) forget(ids []int64) error {
	if len(ids) == 0 {
		return nil
	}
	for _, id := range ids {
		if err := os.RemoveAll(b.systemRoots(id)); err != nil {
			return err
		}
	}
	b.Published()
	return nil
}
