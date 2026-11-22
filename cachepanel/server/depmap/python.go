package depmap

import (
	_ "embed"
	"regexp"
	"strings"
)

var (
	//go:embed cmake.txt
	cmakeText  string
	cmakeTable = parse(cmakeText)

	requirementName = regexp.MustCompile(`^\s*([A-Za-z0-9][A-Za-z0-9._-]*)`)
	separators      = strings.NewReplacer("_", "-", ".", "-")
)

// Python maps a PEP 508 requirement.
func Python(requirement string) Need {
	match := requirementName.FindStringSubmatch(requirement)
	if match == nil {
		return Need{Name: requirement, Dropped: true}
	}
	name := strings.ToLower(separators.Replace(match[1]))
	return single(name, "python3Packages."+name, "python3Packages.py"+name)
}

// CMake maps a find_package name.
func CMake(name string) Need {
	if attrs, ok := cmakeTable.exact(name); ok {
		return fromTable(name, attrs)
	}
	if rest, ok := strings.CutPrefix(name, "KF6"); ok {
		return single(name, "kdePackages."+strings.ToLower(rest))
	}
	if rest, ok := strings.CutPrefix(name, "KF5"); ok {
		return single(name, "libsForQt5."+strings.ToLower(rest))
	}
	lower := strings.ToLower(name)
	return single(name, lower, name, "lib"+lower)
}

// Build backend packages by module.
var backends = map[string]string{
	"hatchling": "hatchling", "setuptools": "setuptools", "poetry": "poetry-core", "flit_core": "flit-core",
	"pdm": "pdm-backend", "mesonpy": "meson-python", "scikit_build_core": "scikit-build-core", "maturin": "maturin",
}

// PythonBackend maps a backend module.
func PythonBackend(module string) Need {
	root, _, _ := strings.Cut(module, ".")
	if name, ok := backends[root]; ok {
		return Python(name)
	}
	return Python(root)
}
