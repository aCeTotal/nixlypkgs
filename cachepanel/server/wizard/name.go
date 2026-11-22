package wizard

import (
	"regexp"
	"strings"
)

var (
	nameSeparators = regexp.MustCompile(`[-_. ]+`)
	versionWord    = regexp.MustCompile(`^v?[0-9]`)
	fileVersion    = regexp.MustCompile(`[-_.]v?([0-9]+(?:\.[0-9]+)+(?:[-.](?:rc|beta|alpha|pre)[0-9]*)?)`)
	extensions     = regexp.MustCompile(`(?i)(\.tar)?\.[a-z0-9]+$`)
	releaseTag     = regexp.MustCompile(`/v?([0-9]+(?:\.[0-9]+)+)/[^/]+$`)
)

// Download words, not program names.
var noiseWords = map[string]bool{
	"linux": true, "x86": true, "x64": true, "amd64": true, "arm64": true, "aarch64": true, "i386": true, "i686": true,
	"64bit": true, "appimage": true, "portable": true, "setup": true, "release": true, "static": true, "musl": true,
	"gnu": true, "unknown": true, "bin": true, "binary": true, "deb": true, "rpm": true, "universal": true,
}

// guessName reads the program from a file name.
func guessName(file string) string {
	var words []string
	for _, word := range nameSeparators.Split(extensions.ReplaceAllString(file, ""), -1) {
		lower := strings.ToLower(word)
		if versionWord.MatchString(lower) || noiseWords[lower] {
			break
		}
		words = append(words, lower)
	}
	return attrName(strings.Join(words, "-"))
}

// guessVersion tries the file, then the URL.
func guessVersion(url, file string) string {
	if match := fileVersion.FindStringSubmatch(extensions.ReplaceAllString(file, "")); match != nil {
		return match[1]
	}
	if match := releaseTag.FindStringSubmatch(url); match != nil {
		return match[1]
	}
	return "0"
}
