package profiles

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"cachepanel/logtail"
)

const (
	systemsFile        = "systems"
	systemBuildTimeout = 6 * time.Hour
	systemOutputKeep   = 16 << 10
	stopGrace          = 15 * time.Second
)

// buildSystems realises toplevels behind gcroots.
func buildSystems(ctx context.Context, link string, drvPaths []string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, systemBuildTimeout)
	defer cancel()
	if err := os.MkdirAll(filepath.Dir(link), 0o750); err != nil {
		return nil, err
	}
	output := logtail.New(systemOutputKeep)
	var toplevels strings.Builder
	args := []string{"build", "--keep-going", "--print-out-paths", "--out-link", link}
	for _, drvPath := range drvPaths {
		args = append(args, drvPath+"^*")
	}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Stdout, cmd.Stderr = &toplevels, output
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = stopGrace
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%w\n%s", err, output.String())
	}
	return strings.Fields(toplevels.String()), nil
}

// cacheSystems builds, records and pushes toplevels.
func (b *Rebuilder) cacheSystems(ctx context.Context, dir string, drvPaths []string) error {
	pending := filepath.Join(dir, "pending")
	defer func() { _ = os.RemoveAll(pending) }()
	toplevels, err := buildSystems(ctx, filepath.Join(pending, "system"), drvPaths)
	if err != nil {
		return err
	}
	// Roots first, so collection keeps them.
	if err := os.WriteFile(filepath.Join(dir, systemsFile), []byte(strings.Join(toplevels, "\n")), 0o640); err != nil {
		return err
	}
	return b.cache.Push(ctx, toplevels...)
}

// Released lists systems the cache keeps.
func (b *Rebuilder) Released() ([]string, error) {
	files, err := filepath.Glob(filepath.Join(b.checksDir, "roots", "*", "*", systemsFile))
	if err != nil {
		return nil, err
	}
	var toplevels []string
	for _, file := range files {
		content, err := os.ReadFile(file)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		toplevels = append(toplevels, strings.Fields(string(content))...)
	}
	return toplevels, nil
}
