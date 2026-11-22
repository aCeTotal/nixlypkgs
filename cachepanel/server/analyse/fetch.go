package analyse

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"
)

const fetchTimeout = 20 * time.Minute

// Fetched is a source in the store.
type Fetched struct {
	Path string
	Hash string
	// Rev and Modified: repositories only.
	Rev      string
	Modified time.Time
}

// File downloads a URL as a flat file.
func File(ctx context.Context, url, name string) (Fetched, error) {
	var out struct {
		Hash      string `json:"hash"`
		StorePath string `json:"storePath"`
	}
	err := nixJSON(ctx, &out, "store", "prefetch-file", "--json", "--hash-type", "sha256", "--name", name, url)
	return Fetched{Path: out.StorePath, Hash: out.Hash}, err
}

// Repository locks a flake-style reference.
func Repository(ctx context.Context, ref string) (Fetched, error) {
	var out struct {
		Hash      string `json:"hash"`
		StorePath string `json:"storePath"`
		Locked    struct {
			Rev          string `json:"rev"`
			LastModified int64  `json:"lastModified"`
		} `json:"locked"`
	}
	err := nixJSON(ctx, &out, "flake", "prefetch", "--json", ref)
	return Fetched{Path: out.StorePath, Hash: out.Hash, Rev: out.Locked.Rev, Modified: time.Unix(out.Locked.LastModified, 0).UTC()}, err
}

func nixJSON(ctx context.Context, into any, args ...string) error {
	ctx, cancel := context.WithTimeout(ctx, fetchTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("nix %s: %w\n%s", args[0], err, stderr.String())
	}
	return json.Unmarshal(out, into)
}
