package source

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"cachepanel/auth"
	"cachepanel/rest"
)

const (
	maxChanges = 100
	maxMessage = 10 << 10
	// A missing object deletes an index entry.
	deletion = "0 0000000000000000000000000000000000000000"
)

var (
	errMoved     = rest.Conflict("source_moved", "main moved on since you opened this; reload and make your change again")
	errUnchanged = rest.Unprocessable("unchanged", "Nothing would change")
	errMessage   = rest.Unprocessable("invalid_message", "Describe the change in a message")
	errChanges   = rest.Unprocessable("invalid_changes", "Change between one and 100 files of at most 1 MiB")
	errFolder    = rest.Unprocessable("is_folder", "A folder has that path")
	errRoot      = rest.Unprocessable("root_commit", "The first commit cannot be reverted")
	errConflict  = rest.Conflict("revert_conflict", "Later changes touch the same lines; revert it by hand")
)

// FileChange writes a file, or deletes it when Content is nil.
type FileChange struct {
	Path    string  `json:"path"`
	Content *string `json:"content"`
}

// Edit is one commit made in the panel.
type Edit struct {
	Base    string       `json:"base"`
	Message string       `json:"message"`
	Changes []FileChange `json:"changes"`
}

// Reversal undoes one commit on top of Base.
type Reversal struct {
	Base   string `json:"base"`
	Commit string `json:"-"`
}

// Author signs panel commits.
type Author struct {
	Name  string
	Email string
}

func (a Author) env() []string {
	return []string{
		"GIT_AUTHOR_NAME=" + a.Name, "GIT_AUTHOR_EMAIL=" + a.Email,
		"GIT_COMMITTER_NAME=" + a.Name, "GIT_COMMITTER_EMAIL=" + a.Email,
	}
}

func (e Edit) validate() error {
	if !shaPattern.MatchString(e.Base) {
		return errMoved
	}
	if strings.TrimSpace(e.Message) == "" || len(e.Message) > maxMessage {
		return errMessage
	}
	if len(e.Changes) == 0 || len(e.Changes) > maxChanges {
		return errChanges
	}
	for _, change := range e.Changes {
		if !validPath(change.Path) {
			return errPath
		}
		if change.Content != nil && len(*change.Content) > maxFile {
			return errChanges
		}
	}
	return nil
}

// Commit writes an edit as a fast-forward of main.
func (r *Repo) Commit(ctx context.Context, edit Edit, author Author) (string, error) {
	if err := edit.validate(); err != nil {
		return "", err
	}
	if err := r.expect(ctx, edit.Base); err != nil {
		return "", err
	}
	work, err := os.MkdirTemp("", "source-edit-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(work) }()
	index := []string{"GIT_INDEX_FILE=" + filepath.Join(work, "index")}
	if _, err := r.run(ctx, call{args: []string{"read-tree", edit.Base}, env: index}); err != nil {
		return "", err
	}
	entries, err := r.entries(ctx, edit, work)
	if err != nil {
		return "", err
	}
	if _, err := r.run(ctx, call{args: []string{"update-index", "-z", "--index-info"}, stdin: strings.NewReader(entries), env: index}); err != nil {
		return "", err
	}
	tree, err := r.run(ctx, call{args: []string{"write-tree"}, env: index})
	if err != nil {
		return "", err
	}
	return r.advance(ctx, edit.Base, strings.TrimSpace(tree), edit.Message+"\n", author)
}

// entries turns changes into --index-info records.
func (r *Repo) entries(ctx context.Context, edit Edit, work string) (string, error) {
	modes, err := r.modes(ctx, edit)
	if err != nil {
		return "", err
	}
	var paths strings.Builder
	written := []FileChange{}
	for i, change := range edit.Changes {
		if change.Content == nil {
			continue
		}
		file := filepath.Join(work, strconv.Itoa(i))
		if err := os.WriteFile(file, []byte(*change.Content), 0o600); err != nil {
			return "", err
		}
		paths.WriteString(file + "\n")
		written = append(written, change)
	}
	oids := []string{}
	if len(written) > 0 {
		out, err := r.run(ctx, call{args: []string{"hash-object", "-w", "--stdin-paths"}, stdin: strings.NewReader(paths.String())})
		if err != nil {
			return "", err
		}
		oids = strings.Fields(out)
	}
	var records strings.Builder
	for i, change := range written {
		mode := modes[change.Path]
		if mode == "" {
			mode = "100644"
		}
		fmt.Fprintf(&records, "%s %s\t%s\x00", mode, oids[i], change.Path)
	}
	for _, change := range edit.Changes {
		if change.Content == nil {
			fmt.Fprintf(&records, "%s\t%s\x00", deletion, change.Path)
		}
	}
	return records.String(), nil
}

// modes keeps executables executable.
func (r *Repo) modes(ctx context.Context, edit Edit) (map[string]string, error) {
	args := []string{"ls-tree", "-z", edit.Base, "--"}
	for _, change := range edit.Changes {
		args = append(args, change.Path)
	}
	out, err := r.read(ctx, args...)
	if err != nil {
		return nil, err
	}
	modes := map[string]string{}
	for record := range strings.SplitSeq(strings.TrimSuffix(out, "\x00"), "\x00") {
		meta, path, found := strings.Cut(record, "\t")
		fields := strings.Fields(meta)
		if !found || len(fields) != 3 {
			continue
		}
		if fields[1] == "tree" {
			return nil, errFolder
		}
		modes[path] = fields[0]
	}
	return modes, nil
}

// Revert undoes a commit on top of main.
func (r *Repo) Revert(ctx context.Context, undo Reversal, author Author) (string, error) {
	if !shaPattern.MatchString(undo.Commit) {
		return "", rest.NotFound()
	}
	if err := r.expect(ctx, undo.Base); err != nil {
		return "", err
	}
	details, err := r.Show(ctx, undo.Commit)
	if err != nil {
		return "", err
	}
	if details.Parent == "" {
		return "", errRoot
	}
	tree, err := r.read(ctx, "merge-tree", "--write-tree", "--merge-base="+undo.Commit, undo.Base, details.Parent)
	if exit, ok := errors.AsType[*exec.ExitError](err); ok && exit.ExitCode() == 1 {
		return "", errConflict
	}
	if err != nil {
		return "", err
	}
	message := fmt.Sprintf("Revert %q\n\nThis reverts commit %s.\n", details.Subject, undo.Commit)
	return r.advance(ctx, undo.Base, strings.Fields(tree)[0], message, author)
}

// expect refuses a stale base.
func (r *Repo) expect(ctx context.Context, base string) error {
	head, err := r.Head(ctx)
	if err != nil {
		return err
	}
	if head != base {
		return errMoved
	}
	return nil
}

// advance commits a tree and moves main only from base.
func (r *Repo) advance(ctx context.Context, base, tree, message string, author Author) (string, error) {
	current, err := r.read(ctx, "rev-parse", base+"^{tree}")
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(current) == tree {
		return "", errUnchanged
	}
	out, err := r.run(ctx, call{args: []string{"commit-tree", tree, "-p", base, "-F", "-"}, stdin: strings.NewReader(message), env: author.env()})
	if err != nil {
		return "", err
	}
	commit := strings.TrimSpace(out)
	if _, err := r.read(ctx, "update-ref", r.ref(), commit, base); err != nil {
		return "", errMoved
	}
	return commit, nil
}

// Author signs as the signed-in user.
func (r *Repo) Author(req *http.Request) Author {
	name := auth.From(req.Context()).Username
	host := "localhost"
	if parsed, err := url.Parse(r.public); err == nil {
		host = parsed.Hostname()
	}
	return Author{Name: name, Email: name + "@" + host}
}
