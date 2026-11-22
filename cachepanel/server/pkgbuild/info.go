package pkgbuild

import (
	"slices"
	"strings"
)

// Info is what a PKGBUILD declares.
type Info struct {
	Base        string
	Names       []string
	Version     string
	Release     string
	Epoch       string
	Description string
	URL         string
	Licenses    []string
	Depends     []string
	MakeDepends []string
	Sources     []string
	NoExtract   []string
	Options     []string
	Functions   []string
}

// parseInfo reads "key = value" lines.
func parseInfo(text string) Info {
	var info Info
	lists := map[string]*[]string{
		"pkgname": &info.Names, "license": &info.Licenses, "depends": &info.Depends,
		"makedepends": &info.MakeDepends, "source": &info.Sources, "noextract": &info.NoExtract,
		"options": &info.Options, "function": &info.Functions,
	}
	scalars := map[string]*string{
		"pkgbase": &info.Base, "pkgver": &info.Version, "pkgrel": &info.Release, "epoch": &info.Epoch,
		"pkgdesc": &info.Description, "url": &info.URL,
	}
	for line := range strings.Lines(text) {
		key, value, ok := strings.Cut(strings.TrimRight(line, "\n"), " = ")
		if !ok || value == "" {
			continue
		}
		if list, ok := lists[key]; ok {
			*list = append(*list, value)
			continue
		}
		if scalar, ok := scalars[key]; ok {
			*scalar = value
		}
	}
	return info
}

func (i Info) Has(function string) bool {
	return slices.Contains(i.Functions, function)
}

// Splits lists the package_* functions.
func (i Info) Splits() []string {
	var names []string
	for _, function := range i.Functions {
		if name, ok := strings.CutPrefix(function, "package_"); ok {
			names = append(names, name)
		}
	}
	return names
}

func (i Info) Option(name string) bool {
	return slices.Contains(i.Options, name)
}
