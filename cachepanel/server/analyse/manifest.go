package analyse

import (
	"encoding/json"
	"io/fs"
	"path"
	"regexp"
	"strings"

	"cachepanel/depmap"
	"cachepanel/recipe"
)

// manifest holds project file facts.
type manifest struct {
	name, version, description, homepage, license string
	tools                                         []string
	needs, python, build                          []depmap.Need
	noBuild, vendored                             bool
}

var (
	sysCrate     = regexp.MustCompile(`(?m)^name = "([a-z0-9_-]+)-sys"$`)
	goModule     = regexp.MustCompile(`(?m)^module\s+(\S+)`)
	majorSuffix  = regexp.MustCompile(`^v[0-9]+$`)
	setupField   = regexp.MustCompile(`(name|version|description|url|license)\s*=\s*["']([^"']+)["']`)
	setupRequire = regexp.MustCompile(`(?s)install_requires\s*=\s*\[(.*?)\]`)
)

// Native libraries behind common -sys crates.
var sysLibraries = map[string]string{
	"openssl": "openssl", "libsqlite3": "sqlite", "alsa": "alsa-lib", "libudev": "systemdLibs", "libdbus": "dbus",
	"gtk": "gtk3", "gtk4": "gtk4", "glib": "glib", "gdk-pixbuf": "gdk-pixbuf", "cairo": "cairo", "pango": "pango",
	"wayland": "wayland", "xkbcommon": "libxkbcommon", "fontconfig": "fontconfig", "servo-fontconfig": "fontconfig",
	"freetype": "freetype", "libz": "zlib", "lzma": "xz", "bzip2": "bzip2", "curl": "curl", "libssh2": "libssh2",
	"onig": "oniguruma", "x11": "libx11", "xcb": "libxcb", "libpulse": "libpulseaudio", "pipewire": "pipewire",
	"libspa": "pipewire", "webkit2gtk": "webkitgtk_4_1", "javascriptcore-rs": "webkitgtk_4_1", "soup3": "libsoup_3",
	"libadwaita": "libadwaita", "libusb1": "libusb1", "hidapi": "hidapi", "libseat": "seatd", "libinput": "libinput",
	"gbm": "libgbm", "drm": "libdrm", "libgit2": "libgit2", "zstd": "zstd", "pcre2": "pcre2",
}

func cargoManifest(root fs.FS) manifest {
	text := readText(root, "Cargo.toml")
	pkg := readTOML(text, "package")
	m := manifest{name: pkg.values["name"], version: pkg.values["version"], description: pkg.values["description"],
		homepage: firstOf(pkg.values["homepage"], pkg.values["repository"]), license: spdxFirst(pkg.values["license"])}
	for _, match := range sysCrate.FindAllStringSubmatch(readText(root, "Cargo.lock"), -1) {
		if attr, ok := sysLibraries[match[1]]; ok {
			m.needs = append(m.needs, depmap.Need{Name: match[1] + "-sys", Alternatives: [][]string{{attr}}})
		}
	}
	if len(m.needs) > 0 {
		m.tools = append(m.tools, "pkg-config")
	}
	return m
}

func goManifest(root fs.FS) manifest {
	m := manifest{vendored: exists(root, "vendor/modules.txt")}
	if match := goModule.FindStringSubmatch(readText(root, "go.mod")); match != nil {
		parts := strings.Split(match[1], "/")
		m.name = parts[len(parts)-1]
		if majorSuffix.MatchString(m.name) && len(parts) > 1 {
			m.name = parts[len(parts)-2]
		}
	}
	return m
}

func pythonManifest(root fs.FS) manifest {
	text := readText(root, "pyproject.toml")
	project := readTOML(text, "project")
	poetry := readTOML(text, "tool.poetry")
	m := manifest{
		name:        firstOf(project.values["name"], poetry.values["name"]),
		version:     firstOf(project.values["version"], poetry.values["version"]),
		description: firstOf(project.values["description"], poetry.values["description"]),
		license:     spdxFirst(firstOf(project.values["license"], project.values["license.table"], poetry.values["license"])),
	}
	requires := readTOML(text, "build-system").arrays["requires"]
	if len(requires) == 0 {
		requires = []string{"setuptools"}
	}
	for _, requirement := range requires {
		m.build = append(m.build, depmap.Python(requirement))
	}
	dependencies := project.arrays["dependencies"]
	for _, key := range sectionKeys(text, "tool.poetry.dependencies") {
		if key != "python" {
			dependencies = append(dependencies, key)
		}
	}
	setup := readText(root, "setup.py")
	for _, field := range setupField.FindAllStringSubmatch(setup, -1) {
		m.fillSetup(field[1], field[2])
	}
	if match := setupRequire.FindStringSubmatch(setup); match != nil {
		dependencies = append(dependencies, quoted(match[1])...)
	}
	for _, dependency := range dependencies {
		m.python = append(m.python, depmap.Python(dependency))
	}
	return m
}

func (m *manifest) fillSetup(key, value string) {
	targets := map[string]*string{"name": &m.name, "version": &m.version, "description": &m.description, "url": &m.homepage, "license": &m.license}
	if *targets[key] == "" {
		*targets[key] = value
	}
}

func npmManifest(root fs.FS) manifest {
	var pkg struct {
		Name        string            `json:"name"`
		Version     string            `json:"version"`
		Description string            `json:"description"`
		Homepage    string            `json:"homepage"`
		License     string            `json:"license"`
		Scripts     map[string]string `json:"scripts"`
	}
	_ = json.Unmarshal([]byte(readText(root, "package.json")), &pkg)
	return manifest{name: path.Base(pkg.Name), version: pkg.Version, description: pkg.Description,
		homepage: pkg.Homepage, license: spdxFirst(pkg.License), noBuild: pkg.Scripts["build"] == ""}
}

var manifests = map[recipe.Builder]func(fs.FS) manifest{
	recipe.Cargo:     cargoManifest,
	recipe.Go:        goManifest,
	recipe.Python:    pythonManifest,
	recipe.Npm:       npmManifest,
	recipe.Meson:     mesonManifest,
	recipe.CMake:     cmakeManifest,
	recipe.Autotools: autotoolsManifest,
	recipe.Make:      func(fs.FS) manifest { return manifest{} },
}

func readText(root fs.FS, name string) string {
	content, err := fs.ReadFile(root, name)
	if err != nil {
		return ""
	}
	return string(content)
}

func exists(root fs.FS, name string) bool {
	_, err := fs.Stat(root, name)
	return err == nil
}

func firstOf(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

// spdxFirst picks one license.
func spdxFirst(expression string) string {
	first, _, _ := strings.Cut(strings.Trim(expression, "() "), " ")
	return strings.TrimSuffix(first, "+")
}
