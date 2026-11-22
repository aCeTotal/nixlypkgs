package analyse

import (
	"errors"
	"os"
	"path/filepath"

	"cachepanel/depmap"
	"cachepanel/recipe"
)

var errUnknown = errors.New("fant verken byggesystem eller programfiler i kilden")

// Build markers, most specific first.
var markers = []struct {
	file    string
	builder recipe.Builder
}{
	{"Cargo.toml", recipe.Cargo},
	{"go.mod", recipe.Go},
	{"meson.build", recipe.Meson},
	{"CMakeLists.txt", recipe.CMake},
	{"configure", recipe.Autotools},
	{"configure.ac", recipe.Autotools},
	{"configure.in", recipe.Autotools},
	{"pyproject.toml", recipe.Python},
	{"setup.py", recipe.Python},
	{"package.json", recipe.Npm},
	{"Makefile", recipe.Make},
	{"makefile", recipe.Make},
	{"GNUmakefile", recipe.Make},
}

// Facts describe a source tree.
type Facts struct {
	Builder recipe.Builder
	// Top is the archive directory, Sub below.
	Top, Sub                                      string
	Name, Version, Description, Homepage, License string
	Tools                                         []string
	Needs, Python, BuildSystem                    []depmap.Need
	NoBuild, Vendored                             bool
	Layout                                        recipe.Layout
}

// Archive inspects an unpacked archive.
func Archive(dir, pname string) (Facts, error) {
	top := single(dir)
	facts, err := Tree(filepath.Join(dir, top), pname)
	facts.Top = top
	facts.Layout.Flat = top == ""
	return facts, err
}

// Tree inspects a source root.
func Tree(root, pname string) (Facts, error) {
	if builder, ok := builderOf(root); ok {
		return sourceFacts(builder, root, ""), nil
	}
	if layout, ok := archiveLayout(root, pname); ok {
		return Facts{Builder: recipe.Prebuilt, Layout: layout}, nil
	}
	for _, sub := range subdirs(root) {
		if builder, ok := builderOf(filepath.Join(root, sub)); ok {
			return sourceFacts(builder, root, sub), nil
		}
	}
	return Facts{}, errUnknown
}

func sourceFacts(builder recipe.Builder, root, sub string) Facts {
	m := manifests[builder](os.DirFS(filepath.Join(root, sub)))
	return Facts{
		Builder: builder, Sub: sub, Name: m.name, Version: m.version, Description: m.description,
		Homepage: m.homepage, License: m.license, Tools: m.tools, Needs: m.needs, Python: m.python,
		BuildSystem: m.build, NoBuild: m.noBuild, Vendored: m.vendored,
	}
}

func builderOf(dir string) (recipe.Builder, bool) {
	for _, marker := range markers {
		if _, err := os.Stat(filepath.Join(dir, marker.file)); err == nil {
			return marker.builder, true
		}
	}
	return "", false
}

// single names dir's only subdirectory.
func single(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 || !entries[0].IsDir() {
		return ""
	}
	return entries[0].Name()
}

func subdirs(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var names []string
	for _, entry := range entries {
		if entry.IsDir() && entry.Name()[0] != '.' {
			names = append(names, entry.Name())
		}
	}
	return names
}
