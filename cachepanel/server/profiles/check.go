package profiles

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"cachepanel/evaluate"
	"cachepanel/realtime"
)

const (
	checkPoll     = time.Minute
	maxCheckError = 16 << 10
)

type pendingCheck struct {
	id      int64
	tree    string
	rev     string
	archive []byte
}

// runChecks evaluates candidates sequentially.
func (b *Rebuilder) runChecks(ctx context.Context) {
	for ctx.Err() == nil {
		next, found, err := b.nextCheck(ctx)
		if err != nil {
			slog.Error("claim type check", "error", err)
		}
		if found {
			b.runCheck(ctx, next)
			continue
		}
		select {
		case <-ctx.Done():
		case <-b.check:
		case <-time.After(checkPoll):
		}
	}
}

func (b *Rebuilder) nextCheck(ctx context.Context) (pendingCheck, bool, error) {
	var next pendingCheck
	err := b.DB.QueryRow(ctx, `
		UPDATE profiles t SET check_state = 'running'
		FROM trees tr
		WHERE tr.hash = t.candidate_tree AND t.id = (
			SELECT id FROM profiles WHERE check_state = 'pending' AND candidate_tree IS NOT NULL AND candidate_rev IS NOT NULL
			ORDER BY id LIMIT 1)
		RETURNING t.id, t.candidate_tree, t.candidate_rev, tr.archive`).
		Scan(&next.id, &next.tree, &next.rev, &next.archive)
	if errors.Is(err, pgx.ErrNoRows) {
		return pendingCheck{}, false, nil
	}
	if err != nil {
		return pendingCheck{}, false, err
	}
	return next, true, nil
}

func (b *Rebuilder) runCheck(ctx context.Context, next pendingCheck) {
	b.Hub.Publish(realtime.ProfileChanged, map[string]int64{"id": next.id})
	tree, err := b.verify(ctx, next)
	if ctx.Err() != nil {
		return
	}
	state, message := "passed", ""
	switch {
	case errors.Is(err, evaluate.ErrSkipped):
		state = "skipped"
	case err != nil:
		state, message = "failed", err.Error()
	}
	if len(message) > maxCheckError {
		message = message[len(message)-maxCheckError:]
	}
	if err := b.recordCheck(ctx, next, tree, state, message); err != nil {
		slog.Error("record type check", "type", next.id, "error", err)
	}
}

// recordCheck promotes signed trees.
func (b *Rebuilder) recordCheck(ctx context.Context, next pendingCheck, tree, state, message string) error {
	tag, err := b.DB.Exec(ctx, `
		UPDATE profiles SET check_state = $4::check_state, check_error = nullif($5, ''), checked_at = now(),
			testing_tree = CASE WHEN $4::check_state IN ('passed', 'skipped') THEN $6 ELSE testing_tree END,
			testing_rev = CASE WHEN $4::check_state IN ('passed', 'skipped') THEN candidate_rev ELSE testing_rev END,
			testing_at = CASE WHEN $4::check_state IN ('passed', 'skipped') THEN now() ELSE testing_at END
		WHERE id = $1 AND candidate_tree = $2 AND candidate_rev = $3 AND check_state = 'running'`,
		next.id, next.tree, next.rev, state, message, tree)
	if err != nil || tag.RowsAffected() == 0 {
		return err
	}
	b.Hub.Publish(realtime.ProfileChanged, map[string]int64{"id": next.id})
	b.Published()
	return nil
}

// unpack stays inside dir.
func unpack(archive []byte, dir string) (err error) {
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return err
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, root.Close()) }()
	compressed, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return err
	}
	reader := tar.NewReader(compressed)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := extract(root, reader, header); err != nil {
			return err
		}
	}
}

func extract(root *os.Root, reader io.Reader, header *tar.Header) error {
	if header.Typeflag == tar.TypeDir {
		return root.MkdirAll(header.Name, 0o750)
	}
	file, err := root.Create(header.Name)
	if err != nil {
		return err
	}
	_, err = io.Copy(file, reader)
	return errors.Join(err, file.Close())
}

// verify builds, signs and rebuilds.
func (b *Rebuilder) verify(ctx context.Context, next pendingCheck) (string, error) {
	work := filepath.Join(b.ChecksDir, next.tree)
	defer func() { _ = os.RemoveAll(work) }()
	flakeRef := b.Mirror.FlakeRef(next.rev)
	hardware, err := evaluate.References(ctx, flakeRef)
	if err != nil {
		return next.tree, err
	}
	drvPaths, err := evaluateTree(ctx, next.archive, filepath.Join(work, "unsigned"), flakeRef, hardware)
	if err != nil {
		return "", err
	}
	unsigned, err := buildSystems(ctx, filepath.Join(work, "roots", "system"), drvPaths)
	if err != nil {
		return "", err
	}
	tree, archive, err := b.signTree(ctx, next.archive, unsigned)
	if err != nil {
		return "", err
	}
	drvPaths, err = evaluateTree(ctx, archive, filepath.Join(work, "signed"), flakeRef, hardware)
	if err != nil {
		return "", err
	}
	roots := b.systemRoots(next.id)
	key := releaseKey(tree, next.rev)
	if err := b.cacheSystems(ctx, filepath.Join(roots, key), drvPaths); err != nil {
		return "", err
	}
	released, err := b.released(ctx, next.id)
	if err != nil {
		return "", err
	}
	return tree, keepOnly(roots, append(released, key))
}

func evaluateTree(ctx context.Context, archive []byte, dir, flakeRef string, hardware []string) ([]string, error) {
	if err := unpack(archive, dir); err != nil {
		return nil, err
	}
	tree := filepath.Join(dir, strings.TrimSuffix(treeRoot, "/"))
	drvPaths := make([]string, 0, len(hardware))
	for _, reference := range hardware {
		drvPath, err := evaluate.System(ctx, flakeRef, reference, tree)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", reference, err)
		}
		drvPaths = append(drvPaths, drvPath)
	}
	return drvPaths, nil
}

func releaseKey(tree, rev string) string {
	return tree + "-" + rev
}

// released names both branches' systems.
func (b *Rebuilder) released(ctx context.Context, id int64) ([]string, error) {
	var testingTree, testingRev, stableTree, stableRev string
	err := b.DB.QueryRow(ctx, `
		SELECT coalesce(testing_tree, ''), coalesce(testing_rev, ''), coalesce(stable_tree, ''), coalesce(stable_rev, '')
		FROM profiles WHERE id = $1`, id).Scan(&testingTree, &testingRev, &stableTree, &stableRev)
	return []string{releaseKey(testingTree, testingRev), releaseKey(stableTree, stableRev)}, err
}

// systemRoots holds checked systems.
func (b *Rebuilder) systemRoots(id int64) string {
	return filepath.Join(b.ChecksDir, "roots", strconv.FormatInt(id, 10))
}

// keepOnly unroots unreleased checked systems.
func keepOnly(dir string, kept []string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if slices.Contains(kept, entry.Name()) {
			continue
		}
		if err := os.RemoveAll(filepath.Join(dir, entry.Name())); err != nil {
			return err
		}
	}
	return nil
}
