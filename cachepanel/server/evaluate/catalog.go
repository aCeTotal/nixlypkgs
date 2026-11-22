package evaluate

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"cachepanel/logtail"
)

const catalogTimeout = 10 * time.Minute

type CatalogModule struct {
	Name      string   `json:"name"`
	Title     string   `json:"title"`
	Category  string   `json:"category"`
	Path      string   `json:"path"`
	X86       bool     `json:"x86"`
	Required  bool     `json:"required"`
	Automatic bool     `json:"automatic"`
	Profiles  []string `json:"profiles"`
}

// Category groups registry modules.
type Category struct {
	Name  string `json:"name"`
	Title string `json:"title"`
}

// Catalog is the repository's module registry.
type Catalog struct {
	Categories []Category      `json:"categories"`
	Modules    []CatalogModule `json:"modules"`
	Pinnable   []string        `json:"pinnable"`
}

func ReadCatalog(ctx context.Context, flakeRef string) (Catalog, error) {
	ctx, cancel := context.WithTimeout(ctx, catalogTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", flakeRef+"#lib.nixlyos",
		"--apply", `o: { categories = o.categories; modules = o.modules; pinnable = o.pinnable "x86_64-linux"; }`)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return Catalog{}, fmt.Errorf("read catalog: %w\n%s", err, stderr.String())
	}
	var catalog Catalog
	err = json.Unmarshal(out, &catalog)
	return catalog, err
}
