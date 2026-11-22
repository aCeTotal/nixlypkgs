package evaluate

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"time"

	"cachepanel/logtail"
)

const (
	packagesAttr  = "packages.x86_64-linux"
	evalWorkers   = "2"
	evalMemoryMiB = "4096"
	evalTimeout   = 30 * time.Minute
	stderrKeep    = 16 << 10
	maxLineBytes  = 64 << 20
)

// Attr is one nix-eval-jobs result line.
type Attr struct {
	Attr    string            `json:"attr"`
	DrvPath string            `json:"drvPath"`
	Name    string            `json:"name"`
	Outputs map[string]string `json:"outputs"`
	Error   string            `json:"error"`
}

// Packages instantiates every cached attribute.
func Packages(ctx context.Context, flakeRef, rootsDir string) ([]Attr, error) {
	ctx, cancel := context.WithTimeout(ctx, evalTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix-eval-jobs",
		"--flake", flakeRef+"#"+packagesAttr,
		"--workers", evalWorkers,
		"--max-memory-size", evalMemoryMiB,
		"--gc-roots-dir", rootsDir,
		"--option", "eval-cache", "false")
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	var attrs []Attr
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 1<<20), maxLineBytes)
	for scanner.Scan() {
		var attr Attr
		if err := json.Unmarshal(scanner.Bytes(), &attr); err != nil {
			continue
		}
		attrs = append(attrs, attr)
	}
	scanErr := scanner.Err()
	_, _ = io.Copy(io.Discard, stdout)
	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("nix-eval-jobs: %w\n%s", err, stderr.String())
	}
	return attrs, scanErr
}
