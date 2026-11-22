package wizard

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"cachepanel/depmap"
	"cachepanel/logtail"
	"cachepanel/nixexpr"
	"cachepanel/recipe"
)

const (
	maxRounds    = 10
	buildTimeout = 3 * time.Hour
	stopGrace    = 15 * time.Second
	logKeep      = 1 << 20
)

var (
	errBuildFailed = errors.New("testbygget feilet, og loggen pekte ikke på noe som kunne rettes automatisk")
	errRounds      = errors.New("testbygget feilet etter for mange automatiske rettelser")
	uploadURL      = regexp.MustCompile(`/api/v1/sources/([0-9a-f]{64})/`)
)

// Outcome is a finished test build.
type Outcome struct {
	Output string   `json:"output"`
	Steps  []string `json:"steps"`
	Hints  []string `json:"hints"`
}

// Build retries while the log explains failures.
func (l *Lab) Build(ctx context.Context, draft *Draft, outLink string, log io.Writer) (Outcome, error) {
	flake, err := l.Flake(ctx)
	if err != nil {
		return Outcome{}, err
	}
	var outcome Outcome
	for round := 1; round <= maxRounds; round++ {
		_, _ = fmt.Fprintf(log, "\n==> Testbygg %d\n", round)
		output, tail, err := l.buildOnce(ctx, flake, *draft, outLink, log)
		if err == nil {
			outcome.Output = output
			draft.Spec.Meta.MainProgram = firstOf(draft.Spec.Meta.MainProgram, mainProgram(output, draft.Spec.Pname))
			return outcome, nil
		}
		if ctx.Err() != nil {
			return outcome, ctx.Err()
		}
		fixes, hints, err := diagnose(ctx, flake, tail, draft.Spec)
		if err != nil {
			return outcome, err
		}
		outcome.Hints = hints
		if len(fixes) == 0 {
			return outcome, errBuildFailed
		}
		for _, fix := range fixes {
			fix.apply(&draft.Spec)
			outcome.Steps = append(outcome.Steps, fix.Text)
			_, _ = fmt.Fprintf(log, "==> %s\n", fix.Text)
		}
	}
	return outcome, errRounds
}

func diagnose(ctx context.Context, flake, log string, spec recipe.Spec) ([]Fix, []string, error) {
	if fixes := hashFix(log, spec); len(fixes) > 0 {
		return fixes, nil, nil
	}
	if fixes := layoutFixes(log, spec); len(fixes) > 0 {
		return fixes, nil, nil
	}
	if fixes := toolchainFixes(log, spec); len(fixes) > 0 {
		return fixes, nil, nil
	}
	wants := missing(log)
	if len(wants) == 0 {
		return nil, knownLimits(log), nil
	}
	needs := make([]depmap.Need, len(wants))
	for i, want := range wants {
		needs[i] = want.need
	}
	results, err := depmap.Resolve(ctx, flake, needs)
	if err != nil {
		return nil, nil, err
	}
	fixes, hints := dependencyFixes(spec, wants, results)
	return fixes, hints, nil
}

// buildOnce returns the log tail on failure.
func (l *Lab) buildOnce(ctx context.Context, flake string, draft Draft, outLink string, log io.Writer) (string, string, error) {
	dir, err := l.materialize(ctx, draft)
	if err != nil {
		return "", err.Error(), err
	}
	defer func() { _ = os.RemoveAll(dir) }()
	ctx, cancel := context.WithTimeout(ctx, buildTimeout)
	defer cancel()
	link := []string{"--no-link"}
	if outLink != "" {
		link = []string{"--out-link", outLink}
	}
	args := append([]string{"build", "--impure", "-L", "--print-out-paths", "--expr",
		nixexpr.Pkgs(flake) + ".callPackage " + nixexpr.String(dir) + " { }"}, link...)
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = stopGrace
	tail := logtail.New(logKeep)
	cmd.Stderr = io.MultiWriter(log, tail)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), tail.String(), err
}

// materialize writes the recipe to disk.
func (l *Lab) materialize(ctx context.Context, draft Draft) (string, error) {
	if err := draft.Spec.Validate(); err != nil {
		return "", err
	}
	source, err := recipe.Render(draft.Spec)
	if err != nil {
		return "", err
	}
	if source, err = recipe.Format(ctx, source); err != nil {
		return "", err
	}
	for _, src := range draft.Spec.Sources {
		if match := uploadURL.FindStringSubmatch(src.URL); src.Kind == recipe.Upload && match != nil {
			if _, err := l.Uploads.Seed(ctx, match[1]); err != nil {
				return "", err
			}
		}
	}
	dir, err := os.MkdirTemp("", "recipe-")
	if err != nil {
		return "", err
	}
	files := map[string][]byte{"default.nix": []byte(source)}
	for name, content := range draft.Files {
		files[name] = content
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), content, 0o600); err != nil {
			return "", errors.Join(err, os.RemoveAll(dir))
		}
	}
	return dir, nil
}

// mainProgram prefers pname, else the sole binary.
func mainProgram(output, pname string) string {
	entries, err := os.ReadDir(filepath.Join(output, "bin"))
	if err != nil {
		return ""
	}
	for _, entry := range entries {
		if entry.Name() == pname {
			return pname
		}
	}
	if len(entries) == 1 {
		return entries[0].Name()
	}
	return ""
}
