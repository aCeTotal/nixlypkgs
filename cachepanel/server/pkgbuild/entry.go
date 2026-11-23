package pkgbuild

import (
	"fmt"
	"net/url"
	"path"
	"regexp"
	"strings"
)

var (
	unsafeName = regexp.MustCompile(`[^A-Za-z0-9+._?=-]`)
	foreignVCS = []string{"hg+", "svn+", "bzr+", "fossil+"}
	pinnedRefs = map[string]bool{"tag": true, "commit": true, "revision": true}
)

// Entry is one makepkg source line.
type Entry struct {
	// Name is the $srcdir entry.
	Name string
	URL  string
	// Git sources pin Rev or follow Branch.
	Git    bool
	Rev    string
	Branch string
	Local  bool
}

// ParseEntry reads [name::][git+]url[#ref].
func ParseEntry(line string) (Entry, error) {
	name, location, renamed := strings.Cut(line, "::")
	if !renamed {
		location = line
	}
	if !strings.Contains(location, "://") {
		return Entry{Name: StoreName(location), Local: true}, nil
	}
	for _, prefix := range foreignVCS {
		if strings.HasPrefix(location, prefix) {
			return Entry{}, fmt.Errorf("source %q uses %s; only git is supported", line, strings.TrimSuffix(prefix, "+"))
		}
	}
	entry := Entry{}
	location, entry.Git = strings.CutPrefix(location, "git+")
	entry.Git = entry.Git || strings.HasPrefix(location, "git://")
	location, fragment, _ := strings.Cut(location, "#")
	if entry.Git {
		location, _, _ = strings.Cut(location, "?")
		key, value, _ := strings.Cut(fragment, "=")
		value, _, _ = strings.Cut(value, "?")
		if pinnedRefs[key] {
			entry.Rev = value
		}
		if key == "branch" {
			entry.Branch = value
		}
	}
	parsed, err := url.Parse(location)
	if err != nil {
		return Entry{}, fmt.Errorf("invalid source %q: %w", line, err)
	}
	entry.URL = parsed.String()
	if !renamed {
		name = defaultName(entry, location)
	}
	entry.Name = StoreName(name)
	return entry, nil
}

func defaultName(entry Entry, location string) string {
	if entry.Git {
		return strings.TrimSuffix(path.Base(strings.TrimRight(location, "/")), ".git")
	}
	return location[strings.LastIndex(location, "/")+1:]
}

// StoreName keeps characters store paths allow.
func StoreName(name string) string {
	return strings.TrimLeft(unsafeName.ReplaceAllString(name, "_"), ".")
}
