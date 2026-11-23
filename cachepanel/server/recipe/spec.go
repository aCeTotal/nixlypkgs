package recipe

import (
	"errors"
	"regexp"
)

// Builder picks the Nix build helper.
type Builder string

const (
	Makepkg   Builder = "makepkg"
	CMake     Builder = "cmake"
	Meson     Builder = "meson"
	Autotools Builder = "autotools"
	Make      Builder = "make"
	Cargo     Builder = "cargo"
	Go        Builder = "go"
	Python    Builder = "python"
	Npm       Builder = "npm"
	AppImage  Builder = "appimage"
	Deb       Builder = "deb"
	Rpm       Builder = "rpm"
	Prebuilt  Builder = "prebuilt"
)

// Vendor names a makepkg build's offline dependency cache.
type Vendor string

const (
	NoVendor    Vendor = ""
	CargoVendor Vendor = "cargo"
	GoVendor    Vendor = "go"
	NpmVendor   Vendor = "npm"
)

type SourceKind string

const (
	URL    SourceKind = "url"
	Upload SourceKind = "upload"
	GitHub SourceKind = "github"
	Git    SourceKind = "git"
	// File ships next to default.nix.
	File SourceKind = "file"
)

type Source struct {
	Kind  SourceKind `json:"kind"`
	Name  string     `json:"name"`
	URL   string     `json:"url,omitempty"`
	Owner string     `json:"owner,omitempty"`
	Repo  string     `json:"repo,omitempty"`
	Rev   string     `json:"rev,omitempty"`
	Hash  string     `json:"hash,omitempty"`
	// History keeps .git for builds that ask it.
	History bool `json:"history,omitempty"`
}

type Meta struct {
	Description string `json:"description"`
	Homepage    string `json:"homepage"`
	License     string `json:"license"`
	MainProgram string `json:"mainProgram"`
}

// Spec is everything a generated derivation needs.
type Spec struct {
	Attr    string   `json:"attr"`
	Pname   string   `json:"pname"`
	Version string   `json:"version"`
	Builder Builder  `json:"builder"`
	Sources []Source `json:"sources"`
	// Root is the unpacked directory to build in.
	Root        string   `json:"root,omitempty"`
	Native      []string `json:"nativeBuildInputs"`
	Inputs      []string `json:"buildInputs"`
	Depends     []string `json:"depends"`
	PythonDeps  []string `json:"pythonDependencies"`
	BuildSystem []string `json:"buildSystem"`
	Flags       []string `json:"flags"`
	Vendor      Vendor   `json:"vendor,omitempty"`
	VendorHash  string   `json:"vendorHash,omitempty"`
	Vendored    bool     `json:"vendored,omitempty"`
	NoBuild     bool     `json:"noBuild,omitempty"`
	SubPackages []string `json:"subPackages,omitempty"`
	Split       string   `json:"split,omitempty"`
	NoExtract   []string `json:"noextract,omitempty"`
	NoStrip     bool     `json:"noStrip,omitempty"`
	Layout      Layout   `json:"layout"`
	Ignored     []string `json:"ignoredLibraries"`
	Meta        Meta     `json:"meta"`
}

// LayoutMode says where a prebuilt tree goes.
type LayoutMode string

const (
	// FHSLayout copies usr/ and friends into $out.
	FHSLayout LayoutMode = "fhs"
	// TreeLayout already looks like $out.
	TreeLayout LayoutMode = "tree"
	// AppLayout lives under $out/opt/<pname>.
	AppLayout LayoutMode = "app"
	// FileLayout is one executable.
	FileLayout LayoutMode = "file"
)

// Layout installs a prebuilt tree.
type Layout struct {
	Mode LayoutMode `json:"mode"`
	// Dirs are the FHS directories present.
	Dirs []string `json:"dirs"`
	// Flat archives lack a single top directory.
	Flat bool `json:"flat"`
	// Drop removes packaging leftovers below $out.
	Drop     []string  `json:"drop"`
	Programs []Program `json:"programs"`
	Desktops []Desktop `json:"desktops"`
	Icons    []string  `json:"icons"`
	Electron bool      `json:"electron"`
}

// Program links an executable into bin.
type Program struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

// Desktop rewrites a launcher's FHS paths.
type Desktop struct {
	Path    string    `json:"path"`
	Rewrite []Rewrite `json:"rewrite"`
}

type Rewrite struct {
	From string `json:"from"`
	To   string `json:"to"`
}

var (
	attrPattern    = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)
	inputPattern   = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*(\.[A-Za-z_][A-Za-z0-9_'-]*)*$`)
	versionPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9.+_~-]*$`)
	filePattern    = regexp.MustCompile(`^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$`)
	licensePattern = regexp.MustCompile(`^[A-Za-z0-9_]*$`)
	errAttr        = errors.New("the attribute may only contain letters, digits, - and _")
	errVersion     = errors.New("the version may only contain letters, digits and . + _ ~ -")
	errInput       = errors.New("invalid dependency")
	errSources     = errors.New("the recipe needs at least one source")
	errFileName    = errors.New("local files may only contain letters, digits and . _ + -")
	errLicense     = errors.New("unknown licence")
)

func (s Spec) Validate() error {
	switch {
	case !attrPattern.MatchString(s.Attr) || !attrPattern.MatchString(s.Pname):
		return errAttr
	case !versionPattern.MatchString(s.Version):
		return errVersion
	case len(s.Sources) == 0:
		return errSources
	case !licensePattern.MatchString(s.Meta.License):
		return errLicense
	}
	for _, source := range s.Sources {
		if source.Kind == File && !filePattern.MatchString(source.Name) {
			return errFileName
		}
	}
	for _, list := range [][]string{s.Native, s.Inputs, s.Depends, s.PythonDeps, s.BuildSystem} {
		for _, input := range list {
			if !inputPattern.MatchString(input) {
				return errInput
			}
		}
	}
	return nil
}
