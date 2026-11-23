package profiles

import (
	"context"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"cachepanel/realtime"
	"cachepanel/rest"
)

var (
	errNothingToApprove = rest.BadRequest("nothing_to_approve", "Nothing to approve")
	errTestingMoved     = rest.Conflict("testing_moved", "Testing has changed. Review the changes again.")
)

type fileChange string

const (
	fileAdded   fileChange = "added"
	fileRemoved fileChange = "removed"
	fileChanged fileChange = "changed"
)

type changedFile struct {
	Path   string     `json:"path"`
	Change fileChange `json:"change"`
}

// awaiting is testing ahead of stable.
type awaiting struct {
	ID          int64         `json:"id"`
	Name        string        `json:"name"`
	Title       string        `json:"title"`
	Platform    string        `json:"platform"`
	TestingTree string        `json:"testingTree"`
	TestingRev  string        `json:"testingRev"`
	TestingAt   time.Time     `json:"testingAt"`
	StableRev   *string       `json:"stableRev"`
	Files       []changedFile `json:"files"`
}

type newCommit struct {
	SHA         string    `json:"sha"`
	Subject     string    `json:"subject"`
	Author      string    `json:"author"`
	CommittedAt time.Time `json:"committedAt"`
}

type approval struct {
	Profiles []struct {
		ID   int64  `json:"id"`
		Tree string `json:"tree"`
		Rev  string `json:"rev"`
	} `json:"profiles"`
}

const pendingFilter = `testing_rev IS NOT NULL AND (testing_tree, testing_rev) IS DISTINCT FROM (stable_tree, stable_rev)`

// pending lists what approval ships.
func (b *Rebuilder) pending(w http.ResponseWriter, r *http.Request) error {
	profiles, err := b.awaiting(r.Context())
	if err != nil {
		return err
	}
	commits, err := b.newCommits(r.Context())
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{"profiles": profiles, "commits": commits})
}

func (b *Rebuilder) awaiting(ctx context.Context) ([]awaiting, error) {
	rows, err := b.db.Query(ctx, `
		SELECT p.id, p.name, p.title, p.platform, p.testing_tree, p.testing_rev, p.testing_at, p.stable_rev, tt.archive, st.archive
		FROM profiles p
			JOIN trees tt ON tt.hash = p.testing_tree
			LEFT JOIN trees st ON st.hash = p.stable_tree
		WHERE `+pendingFilter+` ORDER BY p.id`)
	if err != nil {
		return nil, err
	}
	list := []awaiting{}
	var next awaiting
	var testing, stable []byte
	_, err = pgx.ForEachRow(rows, []any{&next.ID, &next.Name, &next.Title, &next.Platform, &next.TestingTree, &next.TestingRev,
		&next.TestingAt, &next.StableRev, &testing, &stable}, func() error {
		files, err := changes(stable, testing)
		next.Files = files
		list = append(list, next)
		return err
	})
	return list, err
}

// changes diffs two tree archives.
func changes(stable, testing []byte) ([]changedFile, error) {
	before, err := readArchive(stable)
	if err != nil {
		return nil, err
	}
	after, err := readArchive(testing)
	if err != nil {
		return nil, err
	}
	old := make(map[string]string, len(before))
	for _, file := range before {
		old[file.Path] = file.Content
	}
	diff := []changedFile{}
	for _, file := range after {
		content, found := old[file.Path]
		delete(old, file.Path)
		switch {
		case !found:
			diff = append(diff, changedFile{Path: file.Path, Change: fileAdded})
		case content != file.Content:
			diff = append(diff, changedFile{Path: file.Path, Change: fileChanged})
		}
	}
	for path := range old {
		diff = append(diff, changedFile{Path: path, Change: fileRemoved})
	}
	slices.SortFunc(diff, func(a, b changedFile) int { return strings.Compare(a.Path, b.Path) })
	return diff, nil
}

// newCommits spans every pending range.
func (b *Rebuilder) newCommits(ctx context.Context) ([]newCommit, error) {
	rows, err := b.db.Query(ctx, `
		WITH span AS (
			SELECT min(s.position) AS low, max(t.position) AS high
			FROM profiles p
				JOIN commits s ON s.sha = p.stable_rev
				JOIN commits t ON t.sha = p.testing_rev
			WHERE t.position > s.position)
		SELECT c.sha, c.subject, c.author, c.committed_at
		FROM commits c, span WHERE c.position > span.low AND c.position <= span.high
		ORDER BY c.position DESC`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[newCommit])
}

// approve ships exactly what was reviewed.
func (b *Rebuilder) approve(w http.ResponseWriter, r *http.Request) error {
	var req approval
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if len(req.Profiles) == 0 {
		return errNothingToApprove
	}
	ids, trees, revs := make([]int64, len(req.Profiles)), make([]string, len(req.Profiles)), make([]string, len(req.Profiles))
	for i, profile := range req.Profiles {
		ids[i], trees[i], revs[i] = profile.ID, profile.Tree, profile.Rev
	}
	err := pgx.BeginFunc(r.Context(), b.db, func(tx pgx.Tx) error {
		tag, err := tx.Exec(r.Context(), `
			UPDATE profiles p SET stable_tree = p.testing_tree, stable_rev = p.testing_rev, stable_at = now()
			FROM unnest($1::bigint[], $2::text[], $3::text[]) AS a(id, tree, rev)
			WHERE p.id = a.id AND p.testing_tree = a.tree AND p.testing_rev = a.rev`, ids, trees, revs)
		if err != nil {
			return err
		}
		var left int
		if err := tx.QueryRow(r.Context(), `SELECT count(*) FROM profiles WHERE `+pendingFilter).Scan(&left); err != nil {
			return err
		}
		if tag.RowsAffected() != int64(len(ids)) || left > 0 {
			return errTestingMoved
		}
		return nil
	})
	if err != nil {
		return err
	}
	b.hub.Publish(realtime.ProfileChanged, map[string]string{})
	b.published()
	return rest.NoContent(w)
}
