package builds

import (
	"context"
	"errors"
	"io"
	"os"

	"github.com/jackc/pgx/v5"

	"cachepanel/rest"
	"cachepanel/versions"
)

const (
	stderrKeep = 16 << 10
	logTail    = 512 << 10
)

var (
	errNotQueueable   = rest.Conflict("not_queueable", "The version is building or already cached")
	errNotCancellable = rest.Conflict("not_cancellable", "The version is neither queued nor building")
	errNotDroppable   = rest.Conflict("not_droppable", "Cancel the build before deleting it from the cache")
	errSelected       = rest.Conflict("selected", "The version is selected or stable – choose another first")
)

// Queue builds a version first.
func (p *Pool) Queue(ctx context.Context, id int64) error {
	var attr string
	err := p.db.QueryRow(ctx, `
		UPDATE versions v SET state = 'queued', priority = true, queued_at = now(), error = NULL
		FROM packages p
		WHERE p.id = v.package_id AND v.id = $1 AND v.state IN ('pending', 'failed', 'cancelled')
		RETURNING p.attr`, id).Scan(&attr)
	if errors.Is(err, pgx.ErrNoRows) {
		return errNotQueueable
	}
	if err != nil {
		return err
	}
	p.Wake()
	p.announce(id, attr)
	return nil
}

// Cancel stops any unfinished build.
func (p *Pool) Cancel(ctx context.Context, id int64) error {
	if p.stopJob(id) {
		return nil
	}
	var attr string
	err := p.db.QueryRow(ctx, `
		UPDATE versions v SET state = 'cancelled', finished_at = now()
		FROM packages p
		WHERE p.id = v.package_id AND v.id = $1 AND v.state = 'queued'
		RETURNING p.attr`, id).Scan(&attr)
	if errors.Is(err, pgx.ErrNoRows) {
		return errNotCancellable
	}
	if err != nil {
		return err
	}
	p.announce(id, attr)
	return nil
}

// Drop deletes a version's cached outputs.
func (p *Pool) Drop(ctx context.Context, id int64) error {
	var attr string
	var selected bool
	err := p.db.QueryRow(ctx, `
		SELECT p.attr, coalesce(v.id IN (p.selected_version_id, p.stable_version_id), false)
		FROM versions v JOIN packages p ON p.id = v.package_id WHERE v.id = $1`, id).Scan(&attr, &selected)
	if err != nil {
		return err
	}
	if selected {
		return errSelected
	}
	tag, err := p.db.Exec(ctx, `
		UPDATE versions SET state = 'pending', closure_bytes = NULL
		WHERE id = $1 AND state IN ('cached', 'failed', 'cancelled', 'queued')`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errNotDroppable
	}
	p.files.removeRoot(id)
	p.cache.Request()
	p.announce(id, attr)
	return nil
}

// Forget cleans up evicted versions.
func (p *Pool) Forget(evicted []versions.Evicted) {
	for _, version := range evicted {
		p.stopJob(version.ID)
		p.files.Forget(version.ID)
	}
	if len(evicted) > 0 {
		p.cache.Request()
	}
}

// LogTail returns a log's end.
func (p *Pool) LogTail(id int64) (tail []byte, err error) {
	file, err := os.Open(p.files.Log(id))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer func() { err = errors.Join(err, file.Close()) }()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if _, err := file.Seek(max(0, info.Size()-logTail), io.SeekStart); err != nil {
		return nil, err
	}
	return io.ReadAll(file)
}
