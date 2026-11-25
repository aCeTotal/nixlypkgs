package recipe

import (
	"crypto/sha256"
	"encoding/base64"
	"path"
	"regexp"
	"strconv"
	"strings"

	"cachepanel/nixexpr"
)

// VendorSlot is the dependency cache's placeholder.
const VendorSlot = 255

var commitPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)

// Placeholder stands in for a hash a build reports.
func Placeholder(slot int) string {
	digest := sha256.Sum256([]byte("nixly-placeholder-" + strconv.Itoa(slot)))
	return "sha256-" + base64.StdEncoding.EncodeToString(digest[:])
}

func hashOr(hash string, slot int) string {
	if hash == "" {
		return Placeholder(slot)
	}
	return hash
}

// fetcher renders a source expression; slot numbers its placeholder.
func (w *writer) fetcher(src Source, slot int) string {
	fields := []string{}
	add := func(key, value string) {
		fields = append(fields, key+" = "+nixexpr.String(value)+";")
	}
	call := func(name string) string {
		return w.use(name) + " {\n  " + strings.Join(fields, "\n  ") + "\n}"
	}
	var fn string
	switch src.Kind {
	case File:
		return "./" + src.Name
	case GitHub:
		fn = "fetchFromGitHub"
		if src.Name != "" && src.Name != "source" {
			add("name", src.Name)
		}
		add("owner", src.Owner)
		add("repo", src.Repo)
		if w.pinned {
			fields = append(fields, "inherit (source) rev hash;")
			return call(fn)
		}
		add(revKey(src.Rev), src.Rev)
	case Git:
		fn = "fetchgit"
		if src.Name != "" {
			add("name", src.Name)
		}
		add("url", src.URL)
		add("rev", src.Rev)
	default:
		fn = "fetchurl"
		if src.Name != "" && src.Name != path.Base(src.URL) {
			add("name", src.Name)
		}
		add("url", src.URL)
	}
	add("hash", hashOr(src.Hash, slot+1))
	if src.History {
		fields = append(fields, "leaveDotGit = true;", "deepClone = true;")
	}
	return call(fn)
}

func revKey(rev string) string {
	if commitPattern.MatchString(rev) {
		return "rev"
	}
	return "tag"
}

// src renders the single-source attribute.
func (w *writer) src(s Spec) {
	w.printf("\n  src = %s;\n\n", indent(w.fetcher(s.Sources[0], 0)))
}
