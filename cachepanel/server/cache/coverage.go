package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os/exec"
	"path/filepath"

	"cachepanel/logtail"
)

// storeHashLength is a store hash.
const storeHashLength = 32

// Coverage is a closure's cache share.
type Coverage struct {
	Paths   int
	Bytes   int64
	Missing []string
}

// Cover finds closure paths without narinfo.
func (c *Cache) Cover(ctx context.Context, roots ...string) (Coverage, error) {
	output := logtail.New(outputKeep)
	cmd := exec.CommandContext(ctx, "nix", append([]string{"path-info", "--json", "--recursive"}, roots...)...)
	cmd.Stderr = output
	out, err := cmd.Output()
	if err != nil {
		return Coverage{}, fmt.Errorf("closure: %w\n%s", err, output.String())
	}
	var closure map[string]struct {
		NarSize int64 `json:"narSize"`
	}
	if err := json.Unmarshal(out, &closure); err != nil {
		return Coverage{}, err
	}
	c.lock.RLock()
	defer c.lock.RUnlock()
	coverage := Coverage{Paths: len(closure)}
	for path, info := range closure {
		coverage.Bytes += info.NarSize
		_, err := fs.Stat(c.files, filepath.Base(path)[:storeHashLength]+narinfoSuffix)
		if errors.Is(err, fs.ErrNotExist) {
			coverage.Missing = append(coverage.Missing, path)
			continue
		}
		if err != nil {
			return Coverage{}, err
		}
	}
	return coverage, nil
}
