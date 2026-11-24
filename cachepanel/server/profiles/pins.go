package profiles

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	pinsFile    = "pins.nix"
	signingFile = "signing.nix"
)

// Pin holds a derivation at one version.
type Pin struct {
	Version int64
	Out     string
}

// testingPins are a revision's versions.
func testingPins(ctx context.Context, db *pgxpool.Pool, rev string) (map[string]Pin, error) {
	rows, err := db.Query(ctx, `
		SELECT p.attr, v.id, v.outputs->>'out'
		FROM packages p
			JOIN commits c ON c.sha = $1
			JOIN versions v ON v.package_id = p.id
		WHERE p.pinnable AND v.state = 'cached' AND v.outputs ? 'out'
			AND (v.id = p.selected_version_id
				OR (p.selected_version_id IS NULL AND c.position BETWEEN v.first_position AND v.last_position))`, rev)
	if err != nil {
		return nil, err
	}
	return collectPins(rows)
}

// stablePins are the approved versions.
func stablePins(ctx context.Context, db *pgxpool.Pool) (map[string]Pin, error) {
	rows, err := db.Query(ctx, `
		SELECT p.attr, v.id, v.outputs->>'out'
		FROM packages p JOIN versions v ON v.id = p.stable_version_id
		WHERE p.pinnable AND v.outputs ? 'out'`)
	if err != nil {
		return nil, err
	}
	return collectPins(rows)
}

func collectPins(rows pgx.Rows) (map[string]Pin, error) {
	pins := map[string]Pin{}
	var attr string
	var pin Pin
	_, err := pgx.ForEachRow(rows, []any{&attr, &pin.Version, &pin.Out}, func() error {
		pins[attr] = pin
		return nil
	})
	return pins, err
}

// pinVersions is what trees.pins records.
func pinVersions(pins map[string]Pin) ([]byte, error) {
	versions := make(map[string]int64, len(pins))
	for attr, pin := range pins {
		versions[attr] = pin.Version
	}
	return json.Marshal(versions)
}

// withPins swaps pins, drops signatures.
func withPins(files []File, pins map[string]Pin) []File {
	kept := make([]File, 0, len(files))
	for _, file := range files {
		if file.Path != pinsFile && file.Path != signingFile {
			kept = append(kept, file)
		}
	}
	return append(kept, File{Path: pinsFile, Content: pinsNix(pins)})
}

// sourceHash hashes the unsigned tree.
func sourceHash(archive []byte) (string, error) {
	if archive == nil {
		return "", nil
	}
	files, err := readArchive(archive)
	if err != nil {
		return "", err
	}
	kept := make([]File, 0, len(files))
	for _, file := range files {
		if file.Path != signingFile {
			kept = append(kept, file)
		}
	}
	hash, _, err := Archive(kept)
	return hash, err
}

func storeTree(ctx context.Context, db *pgxpool.Pool, hash string, archive []byte, pins map[string]Pin) error {
	versions, err := pinVersions(pins)
	if err != nil {
		return err
	}
	_, err = db.Exec(ctx, `
		INSERT INTO trees (hash, archive, pins) VALUES ($1, $2, $3)
		ON CONFLICT (hash) DO UPDATE SET pins = EXCLUDED.pins WHERE trees.pins IS NULL`, hash, archive, versions)
	return err
}
