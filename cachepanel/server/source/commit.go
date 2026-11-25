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
	// robotName signs the panel's own commits.
	robotName  = "nixly-panel"
	maxMessage = 10 << 10
	// Missing objects delete index entries.
	deletion = "0 0000000000000000000000000000000000000000"
)

var (
	errMoved     = rest.Conflict("source_moved", "main moved on since you opened this; reload and make your change again")
	ErrUnchanged = rest.Unprocessable("unchanged", "Nothing would change")
	errMessage   = rest.Unprocessable("invalid_message", "Describe the change in a message")
	errChanges   = rest.Unprocessable("invalid_changes", "Change between one and 100 files of at most 1 MiB")
	errFolder    = rest.Unprocessable("is_folder", "A folder has that path")
	errRoot      = rest.Unprocessable("root_commit", "The first commit cannot be reverted")
	errConflict  = rest.Conflict("revert_conflict", "Later changes touch the same lines; revert it by hand")
)

// FileChange writes, or deletes when nil.
type FileChange struct {
	Path    string  `json:"path"`
	Content *string `json:"content"`
}

// Edit is one panel commit.
type Edit struct {
	Base    string       `json:"base"`
	Message string       `json:"message"`
	Changes []FileChange `json:"changes"`
}

// Reversal undoes one commit.
type Reversal struct {
	Base    string `json:"base"`
	Commit  string `json:"-"`
	Message string `json:"message"`
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
	if !validMessage(e.Message) {
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

// Commit writes an edit on main.
func (r *Repo) Commit(ctx context.Context, edit Edit, author Author) (string, error) {
	if err := edit.validate(); err != nil {
		return "", err
	}
	head, err := r.onto(ctx, edit)
	if err != nil {
		return "", err
	}
	tree, err := r.writeTree(ctx, head, edit)
	if err != nil {
		return "", err
	}
	return r.advance(ctx, head, tree, edit.Message+"\n", author)
}

// Export writes changed main into dir.
func (r *Repo) Export(ctx context.Context, base string, changes []FileChange, dir string) error {
	edit := Edit{Base: base, Changes: changes}
	head, err := r.onto(ctx, edit)
	if err != nil {
		return err
	}
	tree, err := r.writeTree(ctx, head, edit)
	if err != nil {
		return err
	}
	index := []string{"GIT_INDEX_FILE=" + filepath.Join(dir, ".git-export-index")}
	if _, err := r.run(ctx, call{args: []string{"read-tree", tree}, env: index}); err != nil {
		return err
	}
	if _, err := r.run(ctx, call{args: []string{"--work-tree=" + dir, "checkout-index", "--all", "--force"}, env: index}); err != nil {
		return err
	}
	return os.Remove(filepath.Join(dir, ".git-export-index"))
}

// writeTree applies an edit to head.
func (r *Repo) writeTree(ctx context.Context, head string, edit Edit) (string, error) {
	work, err := os.MkdirTemp("", "source-edit-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(work) }()
	index := []string{"GIT_INDEX_FILE=" + filepath.Join(work, "index")}
	if _, err := r.run(ctx, call{args: []string{"read-tree", head}, env: index}); err != nil {
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
	return strings.TrimSpace(tree), err
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

// Revert undoes a commit on main.
func (r *Repo) Revert(ctx context.Context, undo Reversal, author Author) (string, error) {
	if !validMessage(undo.Message) {
		return "", errMessage
	}
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
	message := fmt.Sprintf("%s\n\nThis reverts %s (%s).\n", strings.TrimSpace(undo.Message), undo.Commit, details.Subject)
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

// advance moves main only from base.
func (r *Repo) advance(ctx context.Context, base, tree, message string, author Author) (string, error) {
	current, err := r.read(ctx, "rev-parse", base+"^{tree}")
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(current) == tree {
		return "", ErrUnchanged
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
	return r.signature(auth.From(req.Context()).Username)
}

// Robot signs the panel's own commits.
func (r *Repo) Robot() Author {
	return r.signature(robotName)
}

func (r *Repo) signature(name string) Author {
	host := "localhost"
	if parsed, err := url.Parse(r.public); err == nil {
		host = parsed.Hostname()
	}
	return Author{Name: name, Email: name + "@" + host}
}

// validMessage refuses blank and oversized messages.
func validMessage(message string) bool {
	return strings.TrimSpace(message) != "" && len(message) <= maxMessage
}

// onto refuses edits to moved paths.
func (r *Repo) onto(ctx context.Context, edit Edit) (string, error) {
	head, err := r.Head(ctx)
	if err != nil || head == edit.Base {
		return head, err
	}
	args := []string{"diff", "--quiet", edit.Base, head, "--"}
	for _, change := range edit.Changes {
		args = append(args, change.Path)
	}
	err = r.command(ctx, args...).Run()
	if _, moved := errors.AsType[*exec.ExitError](err); moved {
		return "", errMoved
	}
	return head, err
}
