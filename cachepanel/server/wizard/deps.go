package wizard

import (
	"slices"

	"cachepanel/depmap"
)

// Wrapper hook per GUI toolkit.
var guiToolkits = []struct{ input, hook string }{
	{"gtk4", "wrapGAppsHook4"},
	{"libadwaita", "wrapGAppsHook4"},
	{"gtk3", "wrapGAppsHook3"},
	{"qt6.qtbase", "qt6.wrapQtAppsHook"},
	{"libsForQt5.qtbase", "libsForQt5.wrapQtAppsHook"},
}

func needsOf(names []string, lookup func(string) depmap.Need) []depmap.Need {
	needs := make([]depmap.Need, len(names))
	for i, name := range names {
		needs[i] = lookup(name)
	}
	return needs
}

func appendNew(list []string, attrs ...string) []string {
	for _, attr := range attrs {
		if !slices.Contains(list, attr) {
			list = append(list, attr)
		}
	}
	return list
}

// guiHooks picks wrappers for used toolkits.
func guiHooks(inputs []string) []string {
	var hooks []string
	for _, toolkit := range guiToolkits {
		if !slices.Contains(inputs, toolkit.input) || slices.Contains(hooks, "wrapGAppsHook4") && toolkit.hook == "wrapGAppsHook3" {
			continue
		}
		hooks = appendNew(hooks, toolkit.hook)
	}
	return hooks
}

func (d *Draft) noteMissing(result depmap.Result) {
	if result.Missing {
		d.Notes = append(d.Notes, "No nixpkgs package for "+result.Name+"; add one yourself if the build needs it")
	}
}
