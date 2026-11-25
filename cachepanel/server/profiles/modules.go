package profiles

import (
	"slices"

	"cachepanel/modules"
	"cachepanel/rest"
)

var errModule = rest.Unprocessable("invalid_module", "Choose optional modules the source offers")

func checkModules(entries []modules.Entry, chosen []string) error {
	optional := modules.Optional(entries)
	for _, slug := range chosen {
		if !slices.Contains(optional, slug) {
			return errModule
		}
	}
	return nil
}
