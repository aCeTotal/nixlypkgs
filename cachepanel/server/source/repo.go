package source

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"cachepanel/config"
)

const (
	repoName   = "source.git"
	gitTimeout = 10 * time.Minute
)

// Repo is the panel's own source.
type Repo struct {
	dir    string
	branch string
	public string
}

// At names the repository without touching it.
func At(cfg config.Config) *Repo {
	return &Repo{dir: filepath.Join(cfg.StateDir, repoName), branch: cfg.Branch, public: cfg.PublicURL + "/" + repoName}
}

// Open seeds the repository once.
func Open(ctx context.Context, cfg config.Config) (*Repo, error) {
	r := At(cfg)
	if _, err := os.Stat(filepath.Join(r.dir, "HEAD")); os.IsNotExist(err) {
		if err := r.seed(ctx, cfg.SourceSeed, cfg.Branch); err != nil {
			return nil, fmt.Errorf("seed %s from %s: %w", repoName, cfg.SourceSeed, err)
		}
	}
	// History is append-only; machines fetch by revision.
	settings := [][]string{
		{"receive.denyNonFastForwards", "true"},
		{"receive.denyDeletes", "true"},
		{"uploadpack.allowReachableSHA1InWant", "true"},
		{"core.hooksPath", cfg.Hooks},
	}
	for _, setting := range settings {
		if err := git(ctx, "-C", r.dir, "config", setting[0], setting[1]); err != nil {
			return nil, err
		}
	}
	return r, nil
}

// seed clones beside, then renames.
func (r *Repo) seed(ctx context.Context, url, branch string) error {
	partial := r.dir + ".partial"
	if err := os.RemoveAll(partial); err != nil {
		return err
	}
	if err := git(ctx, "clone", "--quiet", "--bare", "--single-branch", "--branch", branch, url, partial); err != nil {
		return err
	}
	if err := git(ctx, "-C", partial, "remote", "remove", "origin"); err != nil {
		return err
	}
	return os.Rename(partial, r.dir)
}

func (r *Repo) Dir() string {
	return r.dir
}

// Source is what machines lock.
func (r *Repo) Source(sha string) string {
	return "git+" + r.public + "?rev=" + sha
}

func git(ctx context.Context, args ...string) error {
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

// call is one git run inside the repository.
type call struct {
	args  []string
	stdin io.Reader
	env   []string
}

func (r *Repo) run(ctx context.Context, c call) (string, error) {
	var out strings.Builder
	err := r.stream(ctx, &out, c)
	return out.String(), err
}

// stream runs git with its output going to w.
func (r *Repo) stream(ctx context.Context, w io.Writer, c call) error {
	cmd := r.command(ctx, c.args...)
	cmd.Stdin, cmd.Stdout = c.stdin, w
	cmd.Env = append(os.Environ(), c.env...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("git %s: %w: %s", c.args[0], err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

func (r *Repo) read(ctx context.Context, args ...string) (string, error) {
	return r.run(ctx, call{args: args})
}

func (r *Repo) ref() string {
	return "refs/heads/" + r.branch
}

func (r *Repo) Head(ctx context.Context) (string, error) {
	out, err := r.read(ctx, "rev-parse", "--verify", r.ref()+"^{commit}")
	return strings.TrimSpace(out), err
}

func (r *Repo) command(ctx context.Context, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, "git", append([]string{"-C", r.dir}, args...)...)
}
