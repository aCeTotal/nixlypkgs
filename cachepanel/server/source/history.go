package source

import (
	"context"
	"regexp"
	"strconv"
	"strings"
	"time"

	"cachepanel/rest"
)

const (
	pageSize = 50
	maxPatch = 2 << 20
	// Git's empty tree diffs a root commit.
	emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
	logFormat = "%H%x1f%an%x1f%ct%x1f%s"
)

var shaPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)

// Commit is one line of history.
type Commit struct {
	SHA     string    `json:"sha"`
	Author  string    `json:"author"`
	Time    time.Time `json:"time"`
	Subject string    `json:"subject"`
}

// Page is part of the history.
type Page struct {
	Commits []Commit `json:"commits"`
	More    bool     `json:"more"`
}

// Details is a commit and its diff.
type Details struct {
	Commit
	Body      string     `json:"body"`
	Parent    string     `json:"parent"`
	Files     []FileDiff `json:"files"`
	Truncated bool       `json:"truncated"`
}

// FileDiff is one file's change.
type FileDiff struct {
	Path    string `json:"path"`
	OldPath string `json:"oldPath"`
	Status  string `json:"status"`
	Patch   string `json:"patch"`
}

// Log pages through main, optionally for one path.
func (r *Repo) Log(ctx context.Context, path string, skip int) (Page, error) {
	if path != "" && !validPath(path) {
		return Page{}, errPath
	}
	args := []string{"log", "--format=" + logFormat, "-n", strconv.Itoa(pageSize + 1), "--skip=" + strconv.Itoa(skip), r.ref()}
	if path != "" {
		args = append(args, "--", path)
	}
	out, err := r.read(ctx, args...)
	if err != nil {
		return Page{}, err
	}
	commits := []Commit{}
	for line := range strings.SplitSeq(strings.TrimSpace(out), "\n") {
		if commit, ok := parseCommit(line); ok {
			commits = append(commits, commit)
		}
	}
	more := len(commits) > pageSize
	return Page{Commits: commits[:min(len(commits), pageSize)], More: more}, nil
}

func parseCommit(line string) (Commit, bool) {
	fields := strings.SplitN(line, "\x1f", 4)
	if len(fields) != 4 {
		return Commit{}, false
	}
	seconds, err := strconv.ParseInt(fields[2], 10, 64)
	return Commit{SHA: fields[0], Author: fields[1], Time: time.Unix(seconds, 0).UTC(), Subject: fields[3]}, err == nil
}

// Show diffs a commit against its first parent.
func (r *Repo) Show(ctx context.Context, sha string) (Details, error) {
	if !shaPattern.MatchString(sha) {
		return Details{}, rest.NotFound()
	}
	meta, err := r.read(ctx, "log", "-1", "--format="+logFormat+"%x1f%P%x1f%b", sha)
	if err != nil {
		return Details{}, rest.NotFound()
	}
	fields := strings.SplitN(strings.TrimSuffix(meta, "\n"), "\x1f", 6)
	commit, ok := parseCommit(strings.Join(fields[:4], "\x1f"))
	if !ok || len(fields) != 6 {
		return Details{}, rest.NotFound()
	}
	parent, _, _ := strings.Cut(fields[4], " ")
	details := Details{Commit: commit, Body: strings.TrimSpace(fields[5]), Parent: parent}
	from := details.Parent
	if from == "" {
		from = emptyTree
	}
	names, err := r.read(ctx, "diff", "-z", "-M", "--name-status", from, sha)
	if err != nil {
		return Details{}, err
	}
	details.Files = parseNames(names)
	patch, err := r.read(ctx, "diff", "-M", "--no-color", "--no-ext-diff", from, sha)
	if err != nil {
		return Details{}, err
	}
	details.Truncated = len(patch) > maxPatch
	if details.Truncated {
		return details, nil
	}
	// Both diffs list files in the same order.
	for i, section := range splitPatch(patch) {
		if i < len(details.Files) {
			details.Files[i].Patch = section
		}
	}
	return details, nil
}

// parseNames reads -z name-status records.
func parseNames(out string) []FileDiff {
	fields := strings.Split(strings.TrimSuffix(out, "\x00"), "\x00")
	files := []FileDiff{}
	for i := 0; i+1 < len(fields); i += 2 {
		file := FileDiff{Status: fields[i][:1], Path: fields[i+1]}
		// Renames and copies name both paths.
		if (file.Status == "R" || file.Status == "C") && i+2 < len(fields) {
			file.OldPath, file.Path = fields[i+1], fields[i+2]
			i++
		}
		files = append(files, file)
	}
	return files
}

// splitPatch keeps each file's hunks.
func splitPatch(patch string) []string {
	sections := []string{}
	for part := range strings.SplitSeq(strings.TrimPrefix(patch, "diff --git "), "\ndiff --git ") {
		_, hunks, found := strings.Cut(part, "\n@@")
		if found {
			hunks = "@@" + hunks
		}
		sections = append(sections, hunks)
	}
	return sections
}
