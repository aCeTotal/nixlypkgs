package signing

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// SignatureState says who signed.
type SignatureState string

const (
	ActiveCA  SignatureState = "signed"
	OldCA     SignatureState = "old"
	Unsigned  SignatureState = "unsigned"
	NoRelease SignatureState = "none"
)

// Release is a profile's signing state.
type Release struct {
	Profile  string         `json:"profile"`
	Title    string         `json:"title"`
	Platform string         `json:"platform"`
	Stable   SignatureState `json:"stable"`
	Testing  SignatureState `json:"testing"`
}

func (s *Store) releases(ctx context.Context) ([]Release, error) {
	rows, err := s.db.Query(ctx, `
		SELECT p.name, p.title, p.platform, p.stable_tree IS NOT NULL, st.signed_by, p.testing_tree IS NOT NULL, tt.signed_by,
			(SELECT id FROM signing_cas WHERE retired_at IS NULL)
		FROM profiles p
			LEFT JOIN trees st ON st.hash = p.stable_tree
			LEFT JOIN trees tt ON tt.hash = p.testing_tree
		ORDER BY p.id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Release, error) {
		var release Release
		var stable, testing bool
		var stableBy, testingBy, active *int64
		err := row.Scan(&release.Profile, &release.Title, &release.Platform, &stable, &stableBy, &testing, &testingBy, &active)
		release.Stable, release.Testing = signatureState(stable, stableBy, active), signatureState(testing, testingBy, active)
		return release, err
	})
}

func signatureState(released bool, signedBy, active *int64) SignatureState {
	switch {
	case !released:
		return NoRelease
	case signedBy == nil:
		return Unsigned
	case active != nil && *signedBy == *active:
		return ActiveCA
	}
	return OldCA
}
