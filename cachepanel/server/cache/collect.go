package cache

import (
	"bufio"
	"context"
	"errors"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"cachepanel/logtail"
)

const (
	collectSettle  = 10 * time.Second
	collectTimeout = time.Hour
	hashLength     = 32
	narinfoSuffix  = ".narinfo"
)

// Request coalesces collections.
func (c *Cache) Request() {
	select {
	case c.request <- struct{}{}:
	default:
	}
}

// Run collects on request, keeping roots.
func (c *Cache) Run(ctx context.Context, roots Roots) error {
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-c.request:
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(collectSettle):
		}
		c.collect(ctx, roots)
	}
}

// collect sweeps the cache, then the local store.
func (c *Cache) collect(ctx context.Context, roots Roots) {
	ctx, cancel := context.WithTimeout(ctx, collectTimeout)
	defer cancel()
	live, err := roots(ctx)
	if err != nil {
		slog.Warn("garbage collection", "error", err)
		return
	}
	removed, err := c.sweep(live)
	if err != nil {
		slog.Warn("garbage collection", "error", err)
		return
	}
	output := logtail.New(outputKeep)
	cmd := exec.CommandContext(ctx, "nix", "store", "gc")
	cmd.Stdout, cmd.Stderr = output, output
	if err := cmd.Run(); err != nil {
		slog.Warn("garbage collection", "error", err, "output", output.String())
		return
	}
	slog.Info("garbage collection", "cache_files", removed, "output", output.String())
}

// sweep deletes files no root reaches.
func (c *Cache) sweep(roots []string) (int, error) {
	c.lock.Lock()
	defer c.lock.Unlock()
	live, nars, err := c.reach(roots)
	if err != nil {
		return 0, err
	}
	removed := 0
	for _, dir := range []string{".", "nar"} {
		entries, err := os.ReadDir(filepath.Join(c.dir, dir))
		if err != nil {
			return removed, err
		}
		for _, entry := range entries {
			name := filepath.Join(dir, entry.Name())
			if !dead(name, live, nars) {
				continue
			}
			if err := os.Remove(filepath.Join(c.dir, name)); err != nil {
				return removed, err
			}
			removed++
		}
	}
	return removed, nil
}

func dead(name string, live, nars map[string]bool) bool {
	if hash, found := strings.CutSuffix(name, narinfoSuffix); found {
		return !live[hash]
	}
	return filepath.Dir(name) == "nar" && !nars[name]
}

// reach walks references from roots.
func (c *Cache) reach(roots []string) (map[string]bool, map[string]bool, error) {
	live, nars := map[string]bool{}, map[string]bool{}
	queue := make([]string, 0, len(roots))
	for _, root := range roots {
		queue = append(queue, filepath.Base(root))
	}
	for len(queue) > 0 {
		name := queue[len(queue)-1]
		queue = queue[:len(queue)-1]
		if len(name) < hashLength || live[name[:hashLength]] {
			continue
		}
		live[name[:hashLength]] = true
		nar, references, err := c.narinfo(name[:hashLength])
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, nil, err
		}
		nars[nar] = true
		queue = append(queue, references...)
	}
	return live, nars, nil
}

// narinfo reads a path's NAR and references.
func (c *Cache) narinfo(hash string) (nar string, references []string, err error) {
	file, err := os.Open(filepath.Join(c.dir, hash+narinfoSuffix))
	if err != nil {
		return "", nil, err
	}
	defer func() { err = errors.Join(err, file.Close()) }()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, _ := strings.Cut(scanner.Text(), ": ")
		switch key {
		case "URL":
			nar = value
		case "References":
			references = strings.Fields(value)
		}
	}
	return nar, references, scanner.Err()
}
