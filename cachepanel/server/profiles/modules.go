package profiles

import (
	"context"
	"slices"

	"cachepanel/modules"
	"cachepanel/rest"
)

var errModule = rest.Unprocessable("invalid_module", "Choose optional modules the source offers")

// moduleCatalogue is what main offers profiles.
func (b *Rebuilder) moduleCatalogue(ctx context.Context) ([]modules.Entry, error) {
	head, err := b.Source.Head(ctx)
	if err != nil {
		return nil, err
	}
	return modules.Catalogue(ctx, b.Source, head)
}

func checkModules(entries []modules.Entry, chosen []string) error {
	optional := modules.Optional(entries)
	for _, slug := range chosen {
		if !slices.Contains(optional, slug) {
			return errModule
		}
	}
	return nil
}
