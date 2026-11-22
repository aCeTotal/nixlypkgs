package analyse

import (
	"regexp"
	"strings"
)

var (
	tomlHeader = regexp.MustCompile(`^\s*\[([^\[\]]+)\]\s*$`)
	tomlPair   = regexp.MustCompile(`^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$`)
	tomlString = regexp.MustCompile(`"((?:[^"\\]|\\.)*)"|'([^']*)'`)
)

// table holds one TOML section.
type table struct {
	values map[string]string
	arrays map[string][]string
}

// readTOML reads one section's strings.
func readTOML(text, section string) table {
	t := table{values: map[string]string{}, arrays: map[string][]string{}}
	current, pending := "", ""
	for raw := range strings.Lines(text) {
		line := strings.TrimRight(raw, "\r\n")
		if pending != "" {
			t.arrays[pending] = append(t.arrays[pending], quoted(line)...)
			if strings.Contains(line, "]") {
				pending = ""
			}
			continue
		}
		if header := tomlHeader.FindStringSubmatch(line); header != nil {
			current = strings.TrimSpace(header[1])
			continue
		}
		pair := tomlPair.FindStringSubmatch(line)
		if current != section || pair == nil {
			continue
		}
		key, value := pair[1], strings.TrimSpace(pair[2])
		if strings.HasPrefix(value, "[") {
			t.arrays[key] = quoted(value)
			if !strings.Contains(value, "]") {
				pending = key
			}
			continue
		}
		if strings.HasPrefix(value, "{") {
			key += ".table"
		}
		if found := quoted(value); len(found) > 0 {
			t.values[key] = found[0]
		}
	}
	return t
}

func quoted(text string) []string {
	var found []string
	for _, match := range tomlString.FindAllStringSubmatch(text, -1) {
		found = append(found, match[1]+match[2])
	}
	return found
}

// sectionKeys lists a section's keys.
func sectionKeys(text, section string) []string {
	var keys []string
	current := ""
	for raw := range strings.Lines(text) {
		line := strings.TrimRight(raw, "\r\n")
		if header := tomlHeader.FindStringSubmatch(line); header != nil {
			current = strings.TrimSpace(header[1])
			continue
		}
		if pair := tomlPair.FindStringSubmatch(line); current == section && pair != nil {
			keys = append(keys, pair[1])
		}
	}
	return keys
}
