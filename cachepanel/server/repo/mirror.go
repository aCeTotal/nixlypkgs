package repo

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	gitTimeout = 10 * time.Minute
	logFormat  = "%H%x1f%an%x1f%ct%x1f%s"
)

type Commit struct {
	SHA     string
	Subject string
	Author  string
	Time    time.Time
}

// Mirror is a bare clone.
type Mirror struct {
	dir    string
	branch string
}

func Open(ctx context.Context, dir, url, branch string) (*Mirror, error) {
	m := &Mirror{dir: dir, branch: branch}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, err
	}
	if _, err := os.Stat(filepath.Join(dir, "HEAD")); os.IsNotExist(err) {
		if _, err := m.git(ctx, "init", "--bare", "--quiet"); err != nil {
			return nil, err
		}
	}
	_, err := m.git(ctx, "config", "remote.origin.url", url)
	return m, err
}

// Fetch returns the branch head.
func (m *Mirror) Fetch(ctx context.Context) (string, error) {
	ref := "refs/heads/" + m.branch
	if _, err := m.git(ctx, "fetch", "--quiet", "--prune", "--no-tags", "origin", "+"+ref+":"+ref); err != nil {
		return "", err
	}
	out, err := m.git(ctx, "rev-parse", "--verify", ref+"^{commit}")
	return strings.TrimSpace(out), err
}

// Since lists newer commits, oldest-first.
func (m *Mirror) Since(ctx context.Context, base, head string, limit int) ([]Commit, error) {
	args := []string{"log", "--first-parent", "--format=" + logFormat, "-n", strconv.Itoa(limit), head}
	if base != "" && m.known(ctx, base) {
		args = append(args, "--not", base)
	}
	out, err := m.git(ctx, args...)
	if err != nil {
		return nil, err
	}
	commits, err := parseLog(out)
	slices.Reverse(commits)
	return commits, err
}

// Parents lists older commits.
func (m *Mirror) Parents(ctx context.Context, sha string, limit int) ([]Commit, error) {
	out, err := m.git(ctx, "log", "--first-parent", "--format="+logFormat, "--skip=1", "-n", strconv.Itoa(limit), sha)
	if err != nil {
		return nil, err
	}
	return parseLog(out)
}

// Show reads a committed file.
func (m *Mirror) Show(ctx context.Context, sha, path string) (string, error) {
	return m.git(ctx, "show", sha+":"+path)
}

// Dir is the bare repository.
func (m *Mirror) Dir() string {
	return m.dir
}

// FlakeRef evaluates without network access.
func (m *Mirror) FlakeRef(sha string) string {
	return "git+file://" + m.dir + "?rev=" + sha
}

func (m *Mirror) known(ctx context.Context, sha string) bool {
	_, err := m.git(ctx, "cat-file", "-e", sha+"^{commit}")
	return err == nil
}

func (m *Mirror) git(ctx context.Context, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", m.dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", args[0], err, strings.TrimSpace(stderr.String()))
	}
	return string(out), nil
}

func parseLog(out string) ([]Commit, error) {
	var commits []Commit
	for line := range strings.Lines(out) {
		fields := strings.Split(strings.TrimRight(line, "\n"), "\x1f")
		if len(fields) != 4 {
			return nil, fmt.Errorf("unexpected git log line %q", line)
		}
		seconds, err := strconv.ParseInt(fields[2], 10, 64)
		if err != nil {
			return nil, err
		}
		commits = append(commits, Commit{SHA: fields[0], Author: fields[1], Time: time.Unix(seconds, 0), Subject: fields[3]})
	}
	return commits, nil
}
