package analyse

import (
	"path/filepath"
	"strings"
)

// Control reads a Debian package's metadata.
func Control(root string) map[string]string {
	fields := map[string]string{}
	content, err := readIn(filepath.Join(root, "DEBIAN/control"))
	if err != nil {
		return fields
	}
	for line := range strings.Lines(string(content)) {
		key, value, ok := strings.Cut(strings.TrimRight(line, "\n"), ": ")
		if ok && !strings.HasPrefix(key, " ") {
			fields[key] = value
		}
	}
	return fields
}
