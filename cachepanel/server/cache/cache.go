package cache

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sync"

	"cachepanel/logtail"
)

const (
	outputKeep = 16 << 10
	cacheInfo  = "StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 30\n"
)

// Roots lists store paths the cache keeps.
type Roots func(context.Context) ([]string, error)

// Cache is a signed binary cache directory.
type Cache struct {
	dir     string
	key     string
	files   fs.FS
	lock    sync.RWMutex
	request chan struct{}
}

// Open prepares dir; key may be empty for unsigned caches.
func Open(dir, key string) (*Cache, error) {
	if err := os.MkdirAll(filepath.Join(dir, "nar"), 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(dir, "nix-cache-info"), []byte(cacheInfo), 0o644); err != nil {
		return nil, err
	}
	return &Cache{dir: dir, key: key, files: os.DirFS(dir), request: make(chan struct{}, 1)}, nil
}

// Push copies closures in, signed.
func (c *Cache) Push(ctx context.Context, paths ...string) error {
	c.lock.RLock()
	defer c.lock.RUnlock()
	output := logtail.New(outputKeep)
	cmd := exec.CommandContext(ctx, "nix", append([]string{"copy", "--to", c.url()}, paths...)...)
	cmd.Stdout, cmd.Stderr = output, output
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("push to cache: %w\n%s", err, output.String())
	}
	return nil
}

func (c *Cache) url() string {
	url := "file://" + c.dir + "?compression=zstd&parallel-compression=true"
	if c.key != "" {
		url += "&secret-key=" + c.key
	}
	return url
}
