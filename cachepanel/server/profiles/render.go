package profiles

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"cachepanel/nixexpr"
)

// Spec is a profile tree's content.
type Spec struct {
	ID       int64
	Name     string
	Platform string
	Pinned   string
	Packages []string
	Modules  []Module
}

// Module is imported in order.
type Module struct {
	Slug   string `json:"slug"`
	Source string `json:"source"`
}

type File struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

// Files renders the tree's Nix sources.
func Files(spec Spec, pins map[string]string) []File {
	files := []File{
		{Path: "default.nix", Content: defaultNix(spec)},
		{Path: "pins.nix", Content: pinsNix(pins)},
	}
	for _, module := range spec.Modules {
		files = append(files, File{Path: "modules/" + module.Slug + ".nix", Content: module.Source})
	}
	return files
}

func defaultNix(spec Spec) string {
	var b strings.Builder
	b.WriteString("{ lib, pkgs, ... }:\n\n{\n  imports = [\n")
	for _, module := range spec.Modules {
		fmt.Fprintf(&b, "    ./modules/%s.nix\n", module.Slug)
	}
	fmt.Fprintf(&b, "  ];\n\n  nixlyos.mode = lib.mkForce %s;\n", nixexpr.String(spec.Platform))
	b.WriteString("\n  environment.systemPackages = map (path: lib.getAttrFromPath path pkgs) [\n")
	for _, pkg := range spec.Packages {
		b.WriteString("    [")
		for part := range strings.SplitSeq(pkg, ".") {
			b.WriteString(" " + nixexpr.String(part))
		}
		b.WriteString(" ]\n")
	}
	b.WriteString("  ];\n}\n")
	return b.String()
}

func pinsNix(pins map[string]string) string {
	var b strings.Builder
	b.WriteString("{\n")
	for _, attr := range slices.Sorted(maps.Keys(pins)) {
		fmt.Fprintf(&b, "  %s = %s;\n", nixexpr.String(attr), nixexpr.String(pins[attr]))
	}
	b.WriteString("}\n")
	return b.String()
}
