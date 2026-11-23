package wizard

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"regexp"
	"slices"
	"strings"
	"time"

	"cachepanel/repo"
)

const (
	pushAttempts = 3
	gitTimeout   = 5 * time.Minute
	recipesList  = "pkgs/recipes.nix"
	authorName   = "nixly-cachepanel"
	authorEmail  = "cachepanel@nixlyos.local"
)

var (
	errNoRemote = errors.New("publishing is not set up; set publish.remote and publish.keyFile in the module")
	listedAttr  = regexp.MustCompile(`"([A-Za-z0-9_-]+)"`)
)

// Publisher commits recipes to the package repository.
type Publisher struct {
	Mirror *repo.Mirror
	Remote string
	Key    string
	Branch string
	// KnownHosts pins the host key.
	KnownHosts string
}

// Publish writes pkgs/<attr> and pushes one commit.
func (p *Publisher) Publish(ctx context.Context, attr, version string, files map[string][]byte) (string, error) {
	if p.Remote == "" || p.Key == "" {
		return "", errNoRemote
	}
	var err error
	for range pushAttempts {
		var sha string
		if sha, err = p.attempt(ctx, attr, version, files); err == nil {
			return sha, nil
		}
	}
	return "", err
}

func (p *Publisher) attempt(ctx context.Context, attr, version string, files map[string][]byte) (string, error) {
	head, err := p.Mirror.Fetch(ctx)
	if err != nil {
		return "", err
	}
	dir, err := os.MkdirTemp("", "publish-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(dir) }()
	if _, err := p.git(ctx, "", "clone", "--quiet", "--shared", "--no-checkout", p.Mirror.Dir(), dir); err != nil {
		return "", err
	}
	if _, err := p.git(ctx, dir, "checkout", "--quiet", head); err != nil {
		return "", err
	}
	if err := writePackage(dir, attr, files); err != nil {
		return "", err
	}
	steps := [][]string{
		{"add", "-A", "pkgs/" + attr, recipesList},
		{"-c", "user.name=" + authorName, "-c", "user.email=" + authorEmail, "commit", "--quiet", "-m", attr + ": " + version},
		{"push", "--quiet", p.Remote, "HEAD:refs/heads/" + p.Branch},
	}
	for _, step := range steps {
		if _, err := p.git(ctx, dir, step...); err != nil {
			return "", err
		}
	}
	sha, err := p.git(ctx, dir, "rev-parse", "HEAD")
	return strings.TrimSpace(sha), err
}

// writePackage replaces pkgs/<attr> and lists it.
func writePackage(dir, attr string, files map[string][]byte) error {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer func() { _ = root.Close() }()
	pkg := path.Join("pkgs", attr)
	if err := root.RemoveAll(pkg); err != nil {
		return err
	}
	if err := root.MkdirAll(pkg, 0o750); err != nil {
		return err
	}
	for name, content := range files {
		if err := root.WriteFile(path.Join(pkg, name), content, 0o600); err != nil {
			return err
		}
	}
	current, err := root.ReadFile(recipesList)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	attrs := []string{attr}
	for _, match := range listedAttr.FindAllStringSubmatch(string(current), -1) {
		attrs = append(attrs, match[1])
	}
	slices.Sort(attrs)
	var b strings.Builder
	b.WriteString("# Packages made in the cache panel's wizard.\n[\n")
	for _, name := range slices.Compact(attrs) {
		fmt.Fprintf(&b, "  %q\n", name)
	}
	b.WriteString("]\n")
	return root.WriteFile(recipesList, []byte(b.String()), 0o600)
}

func (p *Publisher) git(ctx context.Context, dir string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	command := args[0]
	if dir != "" {
		args = append([]string{"-C", dir}, args...)
	}
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0",
		"GIT_SSH_COMMAND=ssh -i "+p.Key+" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="+p.KnownHosts)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", command, err, strings.TrimSpace(stderr.String()))
	}
	return string(out), nil
}

// PublicKey is what GitHub needs as a deploy key.
func (p *Publisher) PublicKey(ctx context.Context) (string, error) {
	if p.Remote == "" || p.Key == "" {
		return "", errNoRemote
	}
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ssh-keygen", "-y", "-f", p.Key).Output()
	return strings.TrimSpace(string(out)), err
}
