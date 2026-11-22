package profiles

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"

	"cachepanel/logtail"
)

const (
	systemBuildTimeout = 6 * time.Hour
	systemOutputKeep   = 16 << 10
	stopGrace          = 15 * time.Second
)

// buildSystems realises toplevels behind gcroots.
func buildSystems(ctx context.Context, link string, drvPaths []string) error {
	ctx, cancel := context.WithTimeout(ctx, systemBuildTimeout)
	defer cancel()
	if err := os.MkdirAll(filepath.Dir(link), 0o750); err != nil {
		return err
	}
	output := logtail.New(systemOutputKeep)
	args := []string{"build", "--keep-going", "--out-link", link}
	for _, drvPath := range drvPaths {
		args = append(args, drvPath+"^*")
	}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Stdout, cmd.Stderr = output, output
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = stopGrace
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%w\n%s", err, output.String())
	}
	return nil
}
