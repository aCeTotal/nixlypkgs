package profiles

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Defaults match today's machines exactly.
var defaults = []struct {
	name, title, platform, description string
}{
	{"desktop", "Desktop", "desktop", "Stasjonære arbeidsmaskiner"},
	{"laptop", "Laptop", "desktop", "Bærbare maskiner med samme oppsett som desktop"},
	{"htpc", "HTPC", "htpc", "Stueboks med Steam, GeForce NOW og media"},
}

// seed waits for the module catalog.
func seed(ctx context.Context, db *pgxpool.Pool) error {
	names := make([]string, len(defaults))
	titles := make([]string, len(defaults))
	platforms := make([]string, len(defaults))
	descriptions := make([]string, len(defaults))
	for i, d := range defaults {
		names[i], titles[i], platforms[i], descriptions[i] = d.name, d.title, d.platform, d.description
	}
	_, err := db.Exec(ctx, `
		INSERT INTO profiles (name, title, platform, description, catalog)
		SELECT s.name, s.title, s.platform::platform, s.description,
			(SELECT coalesce(array_agg(c.name ORDER BY c.position), '{}') FROM catalog_modules c
			 WHERE c.present AND NOT c.automatic AND (c.required OR s.platform = ANY(c.defaults)))
		FROM unnest($1::text[], $2::text[], $3::text[], $4::text[]) AS s(name, title, platform, description)
		WHERE NOT EXISTS (SELECT 1 FROM profiles) AND EXISTS (SELECT 1 FROM catalog_modules WHERE present)`,
		names, titles, platforms, descriptions)
	return err
}
