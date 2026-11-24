package modules

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"

	"cachepanel/source"
)

const (
	folder        = "nixlyos/modules/"
	catalogueFile = folder + "catalogue.json"
)

// Entry is one module in import order.
type Entry struct {
	Slug        string `json:"slug"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Required    bool   `json:"required"`
}

// Path is where an entry's source lives.
func (e Entry) Path() string {
	return folder + e.Slug + ".nix"
}

// Catalogue reads the modules a commit offers.
func Catalogue(ctx context.Context, repo *source.Repo, rev string) ([]Entry, error) {
	blob, err := repo.FileAt(ctx, rev, catalogueFile)
	if errors.Is(err, source.ErrNoFile) {
		return []Entry{}, nil
	}
	if err != nil {
		return nil, err
	}
	var entries []Entry
	err = json.Unmarshal([]byte(blob.Text), &entries)
	return entries, err
}

// Optional lists slugs a profile may choose.
func Optional(entries []Entry) []string {
	slugs := []string{}
	for _, entry := range entries {
		if !entry.Required {
			slugs = append(slugs, entry.Slug)
		}
	}
	return slugs
}

func find(entries []Entry, slug string) int {
	return slices.IndexFunc(entries, func(entry Entry) bool { return entry.Slug == slug })
}

// encode writes the catalogue as the repo keeps it.
func encode(entries []Entry) (string, error) {
	var b strings.Builder
	encoder := json.NewEncoder(&b)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	err := encoder.Encode(entries)
	return b.String(), err
}
