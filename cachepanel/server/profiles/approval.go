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

// awaiting is a newer base.
type awaiting struct {
	ID          int64         `json:"id"`
	Name        string        `json:"name"`
	Title       string        `json:"title"`
	Platform    string        `json:"platform"`
	TestingTree string        `json:"testingTree"`
	TestingRev  string        `json:"testingRev"`
	TestingAt   time.Time     `json:"testingAt"`
	BaseRev     *string       `json:"baseRev"`
	Files       []changedFile `json:"files"`
}

// derivation awaits stable approval.
type derivation struct {
	Attr          string     `json:"attr"`
	Version       int64      `json:"version"`
	Name          string     `json:"name"`
	BuiltAt       *time.Time `json:"builtAt"`
	StableVersion *int64     `json:"stableVersion"`
	StableName    *string    `json:"stableName"`
}

// stableCheck is stable rebuilding.
type stableCheck struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	State string `json:"state"`
	Error string `json:"error"`
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
	Derivations []struct {
		Attr    string `json:"attr"`
		Version int64  `json:"version"`
	} `json:"derivations"`
}

// pending lists what approval ships.
func (b *Rebuilder) pending(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	profiles, err := b.awaiting(ctx)
	if err != nil {
		return err
	}
	derivations, err := b.derivations(ctx)
	if err != nil {
		return err
	}
	commits, err := b.newCommits(ctx)
	if err != nil {
		return err
	}
	stable, err := b.stableChecks(ctx)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{
		"profiles": profiles, "derivations": derivations, "commits": commits, "stable": stable,
	})
}

func (b *Rebuilder) awaiting(ctx context.Context) ([]awaiting, error) {
	rows, err := b.DB.Query(ctx, `
		SELECT p.id, p.name, p.title, p.platform, p.testing_tree, p.testing_rev, p.testing_at, p.base_rev, tt.archive, bt.archive
		FROM profiles p
			JOIN trees tt ON tt.hash = p.testing_tree
			LEFT JOIN trees bt ON bt.hash = p.base_tree
		WHERE p.testing_rev IS NOT NULL ORDER BY p.id`)
	if err != nil {
		return nil, err
	}
	list := []awaiting{}
	var next awaiting
	var testing, base []byte
	_, err = pgx.ForEachRow(rows, []any{&next.ID, &next.Name, &next.Title, &next.Platform, &next.TestingTree, &next.TestingRev,
		&next.TestingAt, &next.BaseRev, &testing, &base}, func() error {
		files, err := changes(base, testing)
		next.Files = files
		if next.BaseRev == nil || *next.BaseRev != next.TestingRev || len(files) > 0 {
			list = append(list, next)
		}
		return err
	})
	return list, err
}

// changes diffs bases, not pins.
func changes(base, testing []byte) ([]changedFile, error) {
	before, err := readArchive(base)
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
	delete(old, pinsFile)
	delete(old, signingFile)
	diff := []changedFile{}
	for _, file := range after {
		content, found := old[file.Path]
		delete(old, file.Path)
		switch {
		case file.Path == pinsFile || file.Path == signingFile:
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

func (b *Rebuilder) derivations(ctx context.Context) ([]derivation, error) {
	rows, err := b.DB.Query(ctx, `
		SELECT DISTINCT pk.attr, tv.id, tv.name, tv.finished_at, sv.id, sv.name
		FROM profiles p
			JOIN trees t ON t.hash = p.testing_tree
			CROSS JOIN LATERAL jsonb_each_text(t.pins) AS pin(attr, version)
			JOIN packages pk ON pk.attr = pin.attr
			JOIN versions tv ON tv.id = pin.version::bigint
			LEFT JOIN versions sv ON sv.id = pk.stable_version_id
		WHERE tv.id IS DISTINCT FROM pk.stable_version_id
		ORDER BY pk.attr, tv.id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[derivation])
}

func (b *Rebuilder) stableChecks(ctx context.Context) ([]stableCheck, error) {
	rows, err := b.DB.Query(ctx, `
		SELECT id, title, stable_check_state::text, coalesce(stable_check_error, '')
		FROM profiles WHERE stable_check_state IN ('pending', 'running', 'failed') ORDER BY id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[stableCheck])
}

// newCommits spans every pending base.
func (b *Rebuilder) newCommits(ctx context.Context) ([]newCommit, error) {
	rows, err := b.DB.Query(ctx, `
		WITH span AS (
			SELECT min(s.position) AS low, max(t.position) AS high
			FROM profiles p
				JOIN commits s ON s.sha = p.base_rev
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
	if len(req.Profiles) == 0 && len(req.Derivations) == 0 {
		return errNothingToApprove
	}
	waiting, err := b.awaiting(r.Context())
	if err != nil {
		return err
	}
	// One base approval covers every profile.
	if len(req.Profiles) > 0 && len(req.Profiles) != len(waiting) {
		return errTestingMoved
	}
	err = pgx.BeginFunc(r.Context(), b.DB, func(tx pgx.Tx) error {
		if err := approveBase(r.Context(), tx, req); err != nil {
			return err
		}
		return approveDerivations(r.Context(), tx, req)
	})
	if err != nil {
		return err
	}
	b.Hub.Publish(realtime.ProfileChanged, map[string]string{})
	b.Trigger()
	return rest.NoContent(w)
}

func approveBase(ctx context.Context, tx pgx.Tx, req approval) error {
	if len(req.Profiles) == 0 {
		return nil
	}
	ids, trees, revs := make([]int64, len(req.Profiles)), make([]string, len(req.Profiles)), make([]string, len(req.Profiles))
	for i, profile := range req.Profiles {
		ids[i], trees[i], revs[i] = profile.ID, profile.Tree, profile.Rev
	}
	tag, err := tx.Exec(ctx, `
		UPDATE profiles p SET base_tree = p.testing_tree, base_rev = p.testing_rev,
			stable_candidate_tree = NULL, stable_check_state = NULL, stable_check_error = NULL
		FROM unnest($1::bigint[], $2::text[], $3::text[]) AS a(id, tree, rev)
		WHERE p.id = a.id AND p.testing_tree = a.tree AND p.testing_rev = a.rev`, ids, trees, revs)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != int64(len(ids)) {
		return errTestingMoved
	}
	return nil
}

// approveDerivations takes tested versions only.
func approveDerivations(ctx context.Context, tx pgx.Tx, req approval) error {
	if len(req.Derivations) == 0 {
		return nil
	}
	attrs, versions := make([]string, len(req.Derivations)), make([]int64, len(req.Derivations))
	for i, item := range req.Derivations {
		attrs[i], versions[i] = item.Attr, item.Version
	}
	tag, err := tx.Exec(ctx, `
		UPDATE packages pk SET stable_version_id = a.version
		FROM unnest($1::text[], $2::bigint[]) AS a(attr, version)
		WHERE pk.attr = a.attr AND EXISTS (
			SELECT 1 FROM profiles p JOIN trees t ON t.hash = p.testing_tree
			WHERE (t.pins ->> a.attr)::bigint = a.version)`, attrs, versions)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != int64(len(attrs)) {
		return errTestingMoved
	}
	return nil
}
