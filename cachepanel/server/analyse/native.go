package analyse

import (
	"io/fs"
	"regexp"
	"strings"

	"cachepanel/depmap"
)

var (
	mesonProject   = regexp.MustCompile(`project\(\s*'([^']+)'`)
	mesonVersion   = regexp.MustCompile(`(?s)project\(.*?version\s*:\s*'([^']+)'`)
	mesonDep       = regexp.MustCompile(`dependency\(\s*'([^']+)'`)
	cmakeProject   = regexp.MustCompile(`(?i)project\s*\(\s*"?([A-Za-z0-9_.+-]+)`)
	cmakeVersion   = regexp.MustCompile(`(?is)project\s*\([^)]*?VERSION\s+"?([0-9][0-9.]*)`)
	cmakePkgConfig = regexp.MustCompile(`(?is)pkg_check_modules\s*\(\s*\w+((?:\s+[^)\s]+)+)\s*\)`)
	cmakeFind      = regexp.MustCompile(`(?i)find_package\s*\(\s*([A-Za-z0-9_]+)`)
	acInit         = regexp.MustCompile(`AC_INIT\(\s*\[?([^],)]+)\]?\s*,\s*\[?([^],)]+)\]?(?:\s*,\s*\[?[^],)]*\]?)?(?:\s*,\s*\[?([^],)]+)\]?)?`)
	tarnameUnsafe  = regexp.MustCompile(`[^_a-z0-9]`)
	acPkgConfig    = regexp.MustCompile(`PKG_CHECK_MODULES\(\s*\[?\w+\]?\s*,\s*\[?([^\])]+)`)
	cmakeKeywords  = map[string]bool{"REQUIRED": true, "QUIET": true, "IMPORTED_TARGET": true, "GLOBAL": true, "NO_CMAKE_PATH": true, "NO_CMAKE_ENVIRONMENT_PATH": true}
	versionWord    = regexp.MustCompile(`^[<>=]|^[0-9]`)
)

func mesonManifest(root fs.FS) manifest {
	text := readText(root, "meson.build")
	m := manifest{name: submatch(mesonProject, text), version: submatch(mesonVersion, text)}
	for _, match := range mesonDep.FindAllStringSubmatch(text+readText(root, "src/meson.build"), -1) {
		m.needs = append(m.needs, depmap.PkgConfig(match[1]))
	}
	m.tools = []string{"meson", "ninja", "pkg-config"}
	return m
}

func cmakeManifest(root fs.FS) manifest {
	text := readText(root, "CMakeLists.txt")
	m := manifest{name: submatch(cmakeProject, text), version: submatch(cmakeVersion, text), tools: []string{"cmake"}}
	for _, match := range cmakePkgConfig.FindAllStringSubmatch(text, -1) {
		m.needs = append(m.needs, pkgConfigNeeds(strings.Fields(match[1]))...)
		m.tools = append(m.tools, "pkg-config")
	}
	for _, match := range cmakeFind.FindAllStringSubmatch(text, -1) {
		m.needs = append(m.needs, depmap.CMake(match[1]))
	}
	return m
}

func autotoolsManifest(root fs.FS) manifest {
	text := firstOf(readText(root, "configure.ac"), readText(root, "configure.in"))
	m := manifest{}
	if match := acInit.FindStringSubmatch(text); match != nil {
		m.name, m.version = tarname(match[1], match[3]), strings.TrimSpace(match[2])
	}
	for _, match := range acPkgConfig.FindAllStringSubmatch(text, -1) {
		m.needs = append(m.needs, pkgConfigNeeds(strings.Fields(match[1]))...)
		m.tools = append(m.tools, "pkg-config")
	}
	if !exists(root, "configure") {
		m.tools = append(m.tools, "autoreconfHook")
	}
	return m
}

// pkgConfigNeeds skips keywords and version bounds.
func pkgConfigNeeds(words []string) []depmap.Need {
	var needs []depmap.Need
	for _, word := range words {
		word = strings.Trim(word, `"[]`)
		if word == "" || cmakeKeywords[word] || versionWord.MatchString(word) || strings.HasPrefix(word, "$") {
			continue
		}
		needs = append(needs, depmap.PkgConfig(word))
	}
	return needs
}

func submatch(pattern *regexp.Regexp, text string) string {
	if match := pattern.FindStringSubmatch(text); match != nil {
		return match[1]
	}
	return ""
}

// tarname follows autoconf's AC_PACKAGE_TARNAME default.
func tarname(name, explicit string) string {
	if explicit = strings.TrimSpace(explicit); explicit != "" {
		return explicit
	}
	return tarnameUnsafe.ReplaceAllString(strings.ToLower(strings.TrimPrefix(strings.TrimSpace(name), "GNU ")), "-")
}
