package source

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// InputUpdate locks newer inputs; none means all.
type InputUpdate struct {
	Base   string   `json:"base"`
	Inputs []string `json:"inputs"`
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
		// Follows are arrays; only direct inputs update.
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

// UpdateInputs commits a newer lock on top of main.
func (r *Repo) UpdateInputs(ctx context.Context, update InputUpdate, author Author) (string, error) {
	current, err := r.Inputs(ctx)
	if err != nil {
		return "", err
	}
	if current.Head != update.Base {
		return "", errMoved
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
	for _, name := range []string{"flake.nix", lockFile} {
		blob, err := r.FileAt(ctx, update.Base, name)
		if errors.Is(err, ErrNoFile) {
			continue
		}
		if err != nil {
			return "", err
		}
		if err := os.WriteFile(filepath.Join(work, name), []byte(blob.Text), 0o600); err != nil {
			return "", err
		}
	}
	locked, err := lockNewer(ctx, work, update.Inputs)
	if err != nil {
		return "", err
	}
	what := "every input"
	if len(update.Inputs) > 0 {
		what = strings.Join(update.Inputs, ", ")
	}
	edit := Edit{Base: update.Base, Message: "flake.lock: update " + what, Changes: []FileChange{{Path: lockFile, Content: &locked}}}
	return r.Commit(ctx, edit, author)
}

// lockNewer runs nix flake update beside a copy of the flake.
func lockNewer(ctx context.Context, work string, inputs []string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, updateTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", append([]string{"flake", "update"}, inputs...)...)
	cmd.Dir = work
	if out, err := cmd.CombinedOutput(); err != nil {
		return "", fmt.Errorf("nix flake update: %w: %s", err, strings.TrimSpace(string(out)))
	}
	locked, err := os.ReadFile(filepath.Join(work, lockFile))
	return string(locked), err
}
