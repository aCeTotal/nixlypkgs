package upstream

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"cachepanel/logtail"
	"cachepanel/source"
)

const (
	prefetchTimeout = 10 * time.Minute
	vendorTimeout   = 30 * time.Minute
	stderrKeep      = 8 << 10
	// fakeHash makes builds report hashes.
	fakeHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
	system   = "x86_64-linux"
)

var (
	githubURL = regexp.MustCompile(`^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?/?$`)
	gotHash   = regexp.MustCompile(`got:\s+(sha256-[A-Za-z0-9+/]+=*)`)
)

// flakeRef fetches like the derivation.
func flakeRef(url, rev string) string {
	if match := githubURL.FindStringSubmatch(url); match != nil {
		return "github:" + match[1] + "/" + match[2] + "/" + rev
	}
	return "git+" + url + "?rev=" + rev
}

// prefetch hashes a revision's tree.
func prefetch(ctx context.Context, url, rev string) (string, error) {
	out, err := nix(ctx, prefetchTimeout, "flake", "prefetch", "--json", flakeRef(url, rev))
	if err != nil {
		return "", err
	}
	var fetched struct {
		Hash string `json:"hash"`
	}
	return fetched.Hash, json.Unmarshal(out, &fetched)
}

// vendor recomputes vendored hashes.
func vendor(ctx context.Context, repo *source.Repo, base, attr string, next Source) (Source, error) {
	derived := next.derived()
	if len(derived) == 0 {
		return next, nil
	}
	work, err := os.MkdirTemp("", "upstream-vendor-")
	if err != nil {
		return Source{}, err
	}
	defer func() { _ = os.RemoveAll(work) }()
	for _, each := range derived {
		*each.hash = fakeHash
		text, err := next.Encode()
		if err != nil {
			return Source{}, err
		}
		changes := []source.FileChange{{Path: sourcePath(attr), Content: &text}}
		if err := repo.Export(ctx, base, changes, work); err != nil {
			return Source{}, err
		}
		hash, err := reportedHash(ctx, work, attr, each.attr)
		if err != nil {
			return Source{}, err
		}
		*each.hash = hash
	}
	return next, nil
}

// reportedHash reads a failing build's hash.
func reportedHash(ctx context.Context, flake, attr, dependency string) (string, error) {
	target := fmt.Sprintf("path:%s#packages.%s.%s.%s", flake, system, attr, dependency)
	_, err := nix(ctx, vendorTimeout, "build", "--no-link", target)
	if err == nil {
		return "", fmt.Errorf("%s built with a fake hash", dependency)
	}
	match := gotHash.FindStringSubmatch(err.Error())
	if match == nil {
		return "", err
	}
	return match[1], nil
}

// nix skips the global registry.
func nix(ctx context.Context, timeout time.Duration, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", append([]string{"--option", "flake-registry", ""}, args...)...)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("nix %s: %w\n%s", strings.Join(args[:2], " "), err, stderr.String())
	}
	return out, nil
}
