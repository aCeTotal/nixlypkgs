package depmap

import (
	_ "embed"
	"path"
	"strings"
)

var (
	//go:embed arch.txt
	archText string
	//go:embed soname.txt
	sonameText string
	//go:embed pkgconfig.txt
	pkgconfigText string
	//go:embed command.txt
	commandText string
	//go:embed header.txt
	headerText string
)

// none marks unneeded names.
const none = "none"

type rule struct {
	pattern string
	attrs   []string
}

// table keeps order for first match.
type table []rule

func parse(text string) table {
	var t table
	for line := range strings.Lines(text) {
		fields := strings.Fields(line)
		if len(fields) < 2 || strings.HasPrefix(fields[0], "#") {
			continue
		}
		attrs := fields[1:]
		if attrs[0] == none {
			attrs = []string{}
		}
		t = append(t, rule{pattern: fields[0], attrs: attrs})
	}
	return t
}

func (t table) exact(name string) ([]string, bool) {
	for _, r := range t {
		if r.pattern == name {
			return r.attrs, true
		}
	}
	return nil, false
}

func (t table) match(name string) ([]string, bool) {
	for _, r := range t {
		if ok, _ := path.Match(r.pattern, name); ok {
			return r.attrs, true
		}
	}
	return nil, false
}

var (
	archTable      = parse(archText)
	sonameTable    = parse(sonameText)
	pkgconfigTable = parse(pkgconfigText)
	commandTable   = parse(commandText)
	headerTable    = parse(headerText)
)
