package recipe

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"cachepanel/nixexpr"
)

// writer collects a body and the arguments it uses.
type writer struct {
	b    strings.Builder
	args map[string]bool
}

func newWriter() *writer {
	return &writer{args: map[string]bool{"lib": true}}
}

// use records the top-level argument an attr path needs.
func (w *writer) use(attr string) string {
	head, _, _ := strings.Cut(attr, ".")
	w.args[head] = true
	return attr
}

func (w *writer) printf(format string, a ...any) {
	fmt.Fprintf(&w.b, format, a...)
}

func (w *writer) str(name, value string) {
	if value != "" {
		w.printf("  %s = %s;\n", name, nixexpr.String(value))
	}
}

func (w *writer) flag(name string, on bool) {
	if on {
		w.printf("  %s = true;\n", name)
	}
}

// attrs renders a list of package references.
func (w *writer) attrs(name string, items []string) {
	if len(items) == 0 {
		return
	}
	w.printf("  %s = [\n", name)
	for _, item := range items {
		w.printf("    %s\n", w.use(item))
	}
	w.printf("  ];\n")
}

// strings renders a list of string literals.
func (w *writer) strings(name string, items []string) {
	if len(items) == 0 {
		return
	}
	w.printf("  %s = [\n", name)
	for _, item := range items {
		w.printf("    %s\n", nixexpr.String(item))
	}
	w.printf("  ];\n")
}

// script renders an indented string from shell lines.
func (w *writer) script(name string, lines []string) {
	if len(lines) == 0 {
		return
	}
	w.printf("  %s = ''\n", name)
	for _, line := range lines {
		if line == "" {
			w.printf("\n")
			continue
		}
		w.printf("    %s\n", line)
	}
	w.printf("  '';\n")
}

func (w *writer) meta(s Spec, platforms string) {
	w.printf("\n  meta = {\n")
	if s.Meta.Description != "" {
		w.printf("    description = %s;\n", nixexpr.String(s.Meta.Description))
	}
	if s.Meta.Homepage != "" {
		w.printf("    homepage = %s;\n", nixexpr.String(s.Meta.Homepage))
	}
	if s.Meta.License != "" {
		w.printf("    license = lib.licenses.%s;\n", s.Meta.License)
	}
	if s.Meta.MainProgram != "" {
		w.printf("    mainProgram = %s;\n", nixexpr.String(s.Meta.MainProgram))
	}
	w.printf("    platforms = %s;\n  };\n", platforms)
}

func (w *writer) header() string {
	names := slices.Sorted(maps.Keys(w.args))
	names = slices.DeleteFunc(names, func(name string) bool { return name == "lib" })
	return "{\n  lib,\n  " + strings.Join(names, ",\n  ") + ",\n}:\n\n"
}

// indent shifts a rendered expression one level.
func indent(text string) string {
	return strings.ReplaceAll(text, "\n", "\n  ")
}
