package builds

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Roots lists outputs of live versions.
func (p *Pool) Roots(ctx context.Context) ([]string, error) {
	rows, err := p.db.Query(ctx, `
		SELECT o.path FROM versions v, jsonb_each_text(v.outputs) AS o(name, path)
		WHERE v.state IN ('queued', 'building', 'cached')`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}
