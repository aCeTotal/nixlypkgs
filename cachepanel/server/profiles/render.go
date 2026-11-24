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
	Kernel   string
	// KernelSettings differ from the kernel's own.
	KernelSettings map[string]string
	Pinned         string
	Packages       []string
	// Modules are the optional ones the profile chose.
	Modules []string
}

type File struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

// Files renders the tree's Nix sources.
func Files(spec Spec, pins map[string]Pin) []File {
	return []File{
		{Path: "default.nix", Content: defaultNix(spec)},
		{Path: modulesFile, Content: modulesNix(spec.Modules)},
		{Path: pinsFile, Content: pinsNix(pins)},
	}
}

// modulesNix lists chosen modules; nixlypkgs adds the required ones.
func modulesNix(slugs []string) string {
	var b strings.Builder
	b.WriteString("[\n")
	for _, slug := range slices.Sorted(slices.Values(slugs)) {
		fmt.Fprintf(&b, "  %s\n", nixexpr.String(slug))
	}
	b.WriteString("]\n")
	return b.String()
}

func defaultNix(spec Spec) string {
	var b strings.Builder
	b.WriteString("{ lib, pkgs, ... }:\n\n{\n")
	fmt.Fprintf(&b, "  nixlyos.mode = lib.mkForce %s;\n  nixlyos.kernel = lib.mkForce %s;\n", nixexpr.String(spec.Platform), nixexpr.String(spec.Kernel))
	b.WriteString("  nixlyos.kernelSettings = lib.mkForce {")
	for _, knob := range slices.Sorted(maps.Keys(spec.KernelSettings)) {
		fmt.Fprintf(&b, " %s = %s;", nixexpr.String(knob), nixexpr.String(spec.KernelSettings[knob]))
	}
	b.WriteString(" };\n")
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

func pinsNix(pins map[string]Pin) string {
	var b strings.Builder
	b.WriteString("{\n")
	for _, attr := range slices.Sorted(maps.Keys(pins)) {
		fmt.Fprintf(&b, "  %s = %s;\n", nixexpr.String(attr), nixexpr.String(pins[attr].Out))
	}
	b.WriteString("}\n")
	return b.String()
}
