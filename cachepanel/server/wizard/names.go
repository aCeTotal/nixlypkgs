package wizard

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"slices"
	"strings"
	"sync"

	"cachepanel/nixexpr"
)

const searchLimit = 30

// Package sets searched besides top level.
const namesExpr = `let
  pkgs = %s;
  inherit (pkgs) lib;
  nested = set: map (name: set + "." + name) (builtins.attrNames pkgs.${set});
in builtins.attrNames pkgs ++ lib.concatMap nested [ "python3Packages" "qt6" "kdePackages" "libsForQt5" "gst_all_1" ]`

// names caches attributes per revision.
type names struct {
	mu    sync.Mutex
	flake string
	list  []string
}

func (n *names) load(ctx context.Context, flake string) ([]string, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.flake == flake {
		return n.list, nil
	}
	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--json", "--expr", fmt.Sprintf(namesExpr, nixexpr.Pkgs(flake)))
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("list attributes: %w\n%s", err, stderr.String())
	}
	var list []string
	if err := json.Unmarshal(out, &list); err != nil {
		return nil, err
	}
	n.flake, n.list = flake, list
	return list, nil
}

// Search ranks prefixes before substrings.
func (l *Lab) Search(ctx context.Context, query string) ([]string, error) {
	flake, err := l.Flake(ctx)
	if err != nil {
		return nil, err
	}
	list, err := l.names.load(ctx, flake)
	if err != nil {
		return nil, err
	}
	query = strings.ToLower(query)
	var prefix, inside []string
	for _, name := range list {
		lower := strings.ToLower(name)
		switch {
		case strings.HasPrefix(lower, query) || strings.Contains(lower, "."+query):
			prefix = append(prefix, name)
		case strings.Contains(lower, query) && len(inside) < searchLimit:
			inside = append(inside, name)
		}
	}
	slices.SortFunc(prefix, func(a, b string) int { return len(a) - len(b) })
	found := slices.Concat(prefix, inside)
	return found[:min(len(found), searchLimit)], nil
}

// Taken reports nixpkgs owning an attribute.
func (l *Lab) Taken(ctx context.Context, attr string) (bool, error) {
	flake, err := l.Flake(ctx)
	if err != nil {
		return false, err
	}
	expr := nixexpr.Nixpkgs(flake) + " ? " + nixexpr.String(attr)
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--json", "--expr", expr)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return false, fmt.Errorf("check attribute: %w\n%s", err, stderr.String())
	}
	return strings.TrimSpace(string(out)) == "true", nil
}
