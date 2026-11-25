package upstream

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	gitTimeout = 2 * time.Minute
	// logLimit caps listed upstream commits.
	logLimit = 30
)

var (
	numericVersion = regexp.MustCompile(`^[0-9]+(\.[0-9]+)*$`)
	errNoTag       = errors.New("no numeric tag with that prefix")
)

// clone is a blobless upstream copy.
type clone struct {
	dir string
	url string
}

func cloneOf(root, url string) clone {
	sum := sha256.Sum256([]byte(url))
	return clone{dir: filepath.Join(root, hex.EncodeToString(sum[:8])+".git"), url: url}
}

// fetch updates every branch and tag.
func (c clone) fetch(ctx context.Context) error {
	if _, err := os.Stat(filepath.Join(c.dir, "HEAD")); err == nil {
		_, err := c.git(ctx, "fetch", "--quiet", "--prune", "--filter=blob:none", "--", c.url,
			"+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*")
		return err
	}
	partial := c.dir + ".partial"
	if err := os.RemoveAll(partial); err != nil {
		return err
	}
	if _, err := git(ctx, "", "clone", "--quiet", "--bare", "--filter=blob:none", "--", c.url, partial); err != nil {
		return err
	}
	return os.Rename(partial, c.dir)
}

// Latest is the upstream tip.
type Latest struct {
	Rev     string
	Version string
}

// latest resolves what a source follows.
func (c clone) latest(ctx context.Context, s Source) (Latest, error) {
	if s.Tags != nil {
		return c.newestTag(ctx, *s.Tags)
	}
	rev, err := c.git(ctx, "rev-parse", "--verify", "refs/heads/"+s.Branch+"^{commit}")
	if err != nil {
		return Latest{}, err
	}
	// Versions are UTC commit days.
	day, err := c.git(ctx, "log", "-1", "--format=%cd", "--date=format-local:%Y.%m.%d", rev)
	return Latest{Rev: rev, Version: day}, err
}

func (c clone) newestTag(ctx context.Context, prefix string) (Latest, error) {
	out, err := c.git(ctx, "for-each-ref", "--format=%(refname:lstrip=2) %(objectname) %(*objectname)", "refs/tags/"+prefix+"*")
	if err != nil {
		return Latest{}, err
	}
	newest := Latest{}
	for line := range strings.Lines(out) {
		fields := strings.Fields(line)
		version, found := strings.CutPrefix(fields[0], prefix)
		if !found || !numericVersion.MatchString(version) || !newer(version, newest.Version) {
			continue
		}
		// Annotated tags point at their commit.
		newest = Latest{Rev: fields[len(fields)-1], Version: version}
	}
	if newest.Rev == "" {
		return Latest{}, errNoTag
	}
	return newest, nil
}

// newer compares dotted numbers.
func newer(version, than string) bool {
	if than == "" {
		return true
	}
	parse := func(text string) []int {
		parts := []int{}
		for part := range strings.SplitSeq(text, ".") {
			number, _ := strconv.Atoi(part)
			parts = append(parts, number)
		}
		return parts
	}
	return slices.Compare(parse(version), parse(than)) > 0
}

// log lists commits after since.
func (c clone) log(ctx context.Context, since, until string) ([]string, error) {
	span := until
	if _, err := c.git(ctx, "cat-file", "-e", since+"^{commit}"); err == nil {
		span = since + ".." + until
	}
	out, err := c.git(ctx, "log", "--format=%h %s", fmt.Sprintf("--max-count=%d", logLimit), span)
	if err != nil || out == "" {
		return nil, err
	}
	return strings.Split(out, "\n"), nil
}

func (c clone) git(ctx context.Context, args ...string) (string, error) {
	return git(ctx, c.dir, args...)
}

// git runs in dir when set.
func git(ctx context.Context, dir string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	command := args[0]
	if dir != "" {
		args = append([]string{"-C", dir}, args...)
	}
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Env = append(os.Environ(), "TZ=UTC", "GIT_TERMINAL_PROMPT=0")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", command, err, strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(string(out)), nil
}
