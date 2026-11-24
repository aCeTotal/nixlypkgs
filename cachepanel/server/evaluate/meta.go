package evaluate

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"cachepanel/logtail"
)

const metaTimeout = 10 * time.Minute

// Meta is what a revision offers profiles.
type Meta struct {
	// Pinnable lists single-output package attrs.
	Pinnable []string `json:"pinnable"`
	// Kernels is the catalogue, nil before it existed.
	Kernels *json.RawMessage `json:"kernels"`
}

func ReadMeta(ctx context.Context, flakeRef string) (Meta, error) {
	ctx, cancel := context.WithTimeout(ctx, metaTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", flakeRef+"#lib.nixlyos", "--apply",
		`o: { pinnable = o.pinnable "x86_64-linux"; kernels = if o ? kernels then o.kernels "x86_64-linux" else null; }`)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return Meta{}, fmt.Errorf("read metadata: %w\n%s", err, stderr.String())
	}
	var meta Meta
	err = json.Unmarshal(out, &meta)
	return meta, err
}
