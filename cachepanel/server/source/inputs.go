package source

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"cachepanel/rest"
)

const (
	lockFile      = "flake.lock"
	updateTimeout = 10 * time.Minute
)

var errInput = rest.Unprocessable("unknown_input", "Pick inputs the flake declares")

// Input is one locked flake input.
type Input struct {
	Name     string     `json:"name"`
	Source   string     `json:"source"`
	Ref      string     `json:"ref"`
	Rev      string     `json:"rev"`
	Modified *time.Time `json:"modified"`
}

// Inputs is main's lock.
type Inputs struct {
	Head   string  `json:"head"`
	Inputs []Input `json:"inputs"`
}

// InputUpdate locks newer inputs.
type InputUpdate struct {
	Base    string   `json:"base"`
	Inputs  []string `json:"inputs"`
	Message string   `json:"message"`
}

type lockRef struct {
	Type         string `json:"type"`
	Owner        string `json:"owner"`
	Repo         string `json:"repo"`
	Ref          string `json:"ref"`
	Rev          string `json:"rev"`
	URL          string `json:"url"`
	Path         string `json:"path"`
	LastModified int64  `json:"lastModified"`
}

type lock struct {
	Nodes map[string]struct {
		Inputs   map[string]json.RawMessage `json:"inputs"`
		Locked   lockRef                    `json:"locked"`
		Original lockRef                    `json:"original"`
	} `json:"nodes"`
}

// Inputs reads main's flake.lock.
func (r *Repo) Inputs(ctx context.Context) (Inputs, error) {
	head, err := r.Head(ctx)
	if err != nil {
		return Inputs{}, err
	}
	blob, err := r.FileAt(ctx, head, lockFile)
	if errors.Is(err, ErrNoFile) {
		return Inputs{Head: head, Inputs: []Input{}}, nil
	}
	if err != nil {
		return Inputs{}, err
	}
	var parsed lock
	if err := json.Unmarshal([]byte(blob.Text), &parsed); err != nil {
		return Inputs{}, err
	}
	inputs := []Input{}
	for name, target := range parsed.Nodes["root"].Inputs {
		var node string
		// Only direct inputs update.
		if json.Unmarshal(target, &node) != nil {
			continue
		}
		inputs = append(inputs, describe(name, parsed.Nodes[node].Original, parsed.Nodes[node].Locked))
	}
	slices.SortFunc(inputs, func(a, b Input) int { return strings.Compare(a.Name, b.Name) })
	return Inputs{Head: blob.Head, Inputs: inputs}, nil
}

func describe(name string, original, locked lockRef) Input {
	input := Input{Name: name, Ref: original.Ref, Rev: locked.Rev, Source: cmp.Or(original.URL, original.Path)}
	if original.Owner != "" {
		input.Source = original.Type + ":" + original.Owner + "/" + original.Repo
	}
	if locked.LastModified > 0 {
		modified := time.Unix(locked.LastModified, 0).UTC()
		input.Modified = &modified
	}
	return input
}

// UpdateInputs commits a newer lock.
func (r *Repo) UpdateInputs(ctx context.Context, update InputUpdate, author Author) (string, error) {
	if !validMessage(update.Message) {
		return "", errMessage
	}
	current, err := r.Inputs(ctx)
	if err != nil {
		return "", err
	}
	for _, name := range update.Inputs {
		if !slices.ContainsFunc(current.Inputs, func(input Input) bool { return input.Name == name }) {
			return "", errInput
		}
	}
	work, err := os.MkdirTemp("", "source-inputs-")
	if err != nil {
		return "", err
	}
	defer func() { _ = os.RemoveAll(work) }()
	flake, err := r.copyOut(ctx, update.Base, work, "flake.nix")
	if err != nil {
		return "", err
	}
	if _, err := r.copyOut(ctx, update.Base, work, lockFile); err != nil && !errors.Is(err, ErrNoFile) {
		return "", err
	}
	locked, updates, err := lockNewer(ctx, work, update.Inputs)
	if err != nil {
		return "", err
	}
	message := strings.TrimSpace(update.Message)
	if len(updates) > 0 {
		message += "\n\n" + strings.Join(updates, "\n")
	}
	// flake.nix rides along for conflicts.
	edit := Edit{Base: update.Base, Message: message, Changes: []FileChange{{Path: "flake.nix", Content: &flake}, {Path: lockFile, Content: &locked}}}
	return r.Commit(ctx, edit, author)
}

// copyOut writes a rev's file.
func (r *Repo) copyOut(ctx context.Context, rev, dir, name string) (string, error) {
	blob, err := r.FileAt(ctx, rev, name)
	if err != nil {
		return "", err
	}
	return blob.Text, os.WriteFile(filepath.Join(dir, name), []byte(blob.Text), 0o600)
}

// lockNewer updates a flake copy.
func lockNewer(ctx context.Context, work string, inputs []string) (string, []string, error) {
	ctx, cancel := context.WithTimeout(ctx, updateTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", append([]string{"flake", "update"}, inputs...)...)
	cmd.Dir = work
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", nil, fmt.Errorf("nix flake update: %w: %s", err, strings.TrimSpace(string(out)))
	}
	updates := []string{}
	for line := range strings.SplitSeq(string(out), "\n") {
		if strings.Contains(line, "Updated input") || strings.Contains(line, "Added input") {
			updates = append(updates, strings.TrimSpace(line))
		}
	}
	locked, err := fs.ReadFile(os.DirFS(work), lockFile)
	return string(locked), updates, err
}
