package builds

import (
	"context"
	"log/slog"
	"os/exec"
	"time"

	"cachepanel/logtail"
)

const (
	gcSettle  = 10 * time.Second
	gcTimeout = time.Hour
)

// collector coalesces garbage collection requests.
type collector struct {
	request chan struct{}
}

func newCollector() *collector {
	return &collector{request: make(chan struct{}, 1)}
}

func (c *collector) Request() {
	select {
	case c.request <- struct{}{}:
	default:
	}
}

func (c *collector) run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-c.request:
		}
		sleep(ctx, gcSettle)
		c.collect(ctx)
	}
}

func (c *collector) collect(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, gcTimeout)
	defer cancel()
	output := logtail.New(stderrKeep)
	cmd := exec.CommandContext(ctx, "nix", "store", "gc")
	cmd.Stdout, cmd.Stderr = output, output
	if err := cmd.Run(); err != nil {
		slog.Warn("garbage collection", "error", err, "output", output.String())
		return
	}
	slog.Info("garbage collection", "output", output.String())
}
