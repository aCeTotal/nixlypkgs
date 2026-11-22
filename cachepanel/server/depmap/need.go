package depmap

import (
	"regexp"
	"strings"
)

var (
	versionConstraint = regexp.MustCompile(`[<>=:].*$`)
	sonameSuffix      = regexp.MustCompile(`\.so(\..*)?$`)
	pkgconfigVersion  = regexp.MustCompile(`-[0-9.]+$`)
	droppedPrefixes   = []string{"lib32-", "ttf-", "otf-", "noto-fonts", "adobe-source-", "xorg-fonts-"}
	languageSets      = []struct{ prefix, set string }{
		{"python-", "python3Packages."},
		{"haskell-", "haskellPackages."},
		{"ruby-", "rubyPackages."},
		{"lua-", "luaPackages."},
		{"nodejs-", "nodePackages."},
	}
)

// Need lists alternatives, best first.
type Need struct {
	Name         string
	Alternatives [][]string
	// Dropped needs have nothing to add.
	Dropped bool
}

func single(name string, attrs ...string) Need {
	need := Need{Name: name}
	for _, attr := range attrs {
		need.Alternatives = append(need.Alternatives, []string{attr})
	}
	return need
}

func fromTable(name string, attrs []string) Need {
	return Need{Name: name, Alternatives: [][]string{attrs}, Dropped: len(attrs) == 0}
}

// Arch maps an Arch package name.
func Arch(entry string) Need {
	name := strings.TrimSpace(versionConstraint.ReplaceAllString(entry, ""))
	if attrs, ok := archTable.exact(name); ok {
		return fromTable(name, attrs)
	}
	for _, prefix := range droppedPrefixes {
		if strings.HasPrefix(name, prefix) {
			return Need{Name: name, Dropped: true}
		}
	}
	for _, set := range languageSets {
		if rest, ok := strings.CutPrefix(name, set.prefix); ok {
			return single(name, set.set+rest, set.set+"py"+rest, set.set+name)
		}
	}
	if rest, ok := strings.CutPrefix(name, "perl-"); ok {
		return single(name, "perlPackages."+camel(rest))
	}
	if rest, ok := strings.CutPrefix(name, "qt6-"); ok {
		return single(name, "qt6.qt"+strings.ReplaceAll(rest, "-", ""), "kdePackages.qt"+strings.ReplaceAll(rest, "-", ""))
	}
	if rest, ok := strings.CutPrefix(name, "qt5-"); ok {
		return single(name, "libsForQt5.qt"+strings.ReplaceAll(rest, "-", ""))
	}
	for _, suffix := range []string{"-git", "-bin"} {
		if base, ok := strings.CutSuffix(name, suffix); ok {
			return Arch(base)
		}
	}
	return single(name, name, "kdePackages."+name, "libsForQt5."+name, strings.ToLower(name))
}

// Soname maps a missing shared object.
func Soname(name string) Need {
	if attrs, ok := sonameTable.match(name); ok {
		return fromTable(name, attrs)
	}
	stem := sonameSuffix.ReplaceAllString(name, "")
	return single(name, stem, strings.TrimPrefix(stem, "lib"))
}

// PkgConfig maps a pkg-config module.
func PkgConfig(name string) Need {
	if attrs, ok := pkgconfigTable.exact(name); ok {
		return fromTable(name, attrs)
	}
	bare := pkgconfigVersion.ReplaceAllString(name, "")
	return single(name, name, bare, "lib"+bare, strings.TrimPrefix(bare, "lib"))
}

// Command maps a missing build tool.
func Command(name string) Need {
	if attrs, ok := commandTable.exact(name); ok {
		return fromTable(name, attrs)
	}
	return single(name, name)
}

// camel turns file-which into FileWhich.
func camel(name string) string {
	var b strings.Builder
	for part := range strings.SplitSeq(name, "-") {
		if part == "" {
			continue
		}
		b.WriteString(strings.ToUpper(part[:1]) + part[1:])
	}
	return b.String()
}

// Header maps a missing C header.
func Header(name string) Need {
	if attrs, ok := headerTable.match(name); ok {
		return fromTable(name, attrs)
	}
	return Need{Name: name}
}
