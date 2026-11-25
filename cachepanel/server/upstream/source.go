package upstream

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"cachepanel/rest"
	"cachepanel/source"
)

const (
	pkgsDir    = "pkgs"
	sourceFile = "source.json"
)

var (
	revPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)
	errSource  = rest.Unprocessable("invalid_source", "source.json needs an https or file URL, a commit rev, a hash and either a branch or tags")
)

// Source is pkgs/<attr>/source.json.
type Source struct {
	URL string `json:"url"`
	// Branch follows every commit on it.
	Branch string `json:"branch,omitempty"`
	// Tags is the followed tag prefix.
	Tags    *string `json:"tags,omitempty"`
	Rev     string  `json:"rev"`
	Hash    string  `json:"hash"`
	Version string  `json:"version"`
	// Vendored hashes follow Rev.
	CargoHash   string `json:"cargoHash,omitempty"`
	VendorHash  string `json:"vendorHash,omitempty"`
	NpmDepsHash string `json:"npmDepsHash,omitempty"`
}

func sourcePath(attr string) string {
	return pkgsDir + "/" + attr + "/" + sourceFile
}

func (s Source) validate() error {
	remote := strings.HasPrefix(s.URL, "https://") || strings.HasPrefix(s.URL, "file:///")
	follows := (s.Branch != "") != (s.Tags != nil)
	if !remote || !follows || !revPattern.MatchString(s.Rev) || s.Hash == "" {
		return errSource
	}
	return nil
}

// Follows names what the tracker watches.
func (s Source) Follows() string {
	if s.Tags != nil {
		return "tags " + *s.Tags + "*"
	}
	return s.Branch
}

// derived lists vendored hashes.
func (s *Source) derived() []vendored {
	all := []vendored{{&s.CargoHash, "cargoDeps"}, {&s.VendorHash, "goModules"}, {&s.NpmDepsHash, "npmDeps"}}
	kept := []vendored{}
	for _, each := range all {
		if *each.hash != "" {
			kept = append(kept, each)
		}
	}
	return kept
}

// vendored is one dependency hash.
type vendored struct {
	hash *string
	attr string
}

// Encode matches the repo format.
func (s Source) Encode() (string, error) {
	var b strings.Builder
	encoder := json.NewEncoder(&b)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	err := encoder.Encode(s)
	return b.String(), err
}

// Sources reads every source.json at rev.
func Sources(ctx context.Context, repo *source.Repo, rev string) (map[string]Source, map[string]error, error) {
	files, err := repo.FilesNamed(ctx, rev, pkgsDir, sourceFile)
	if err != nil {
		return nil, nil, err
	}
	sources := make(map[string]Source, len(files))
	problems := map[string]error{}
	for attr, text := range files {
		each, err := decodeSource(text)
		if err != nil {
			problems[attr] = fmt.Errorf("%s: %w", sourcePath(attr), err)
			continue
		}
		sources[attr] = each
	}
	return sources, problems, nil
}

func decodeSource(text string) (Source, error) {
	var each Source
	if err := json.Unmarshal([]byte(text), &each); err != nil {
		return Source{}, err
	}
	return each, each.validate()
}
