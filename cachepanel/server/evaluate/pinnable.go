package evaluate

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"cachepanel/logtail"
)

const pinnableTimeout = 10 * time.Minute

// ReadPinnable lists single-output package attrs.
func ReadPinnable(ctx context.Context, flakeRef string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, pinnableTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", flakeRef+"#lib.nixlyos",
		"--apply", `o: o.pinnable "x86_64-linux"`)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("read pinnable: %w\n%s", err, stderr.String())
	}
	var pinnable []string
	err = json.Unmarshal(out, &pinnable)
	return pinnable, err
}
