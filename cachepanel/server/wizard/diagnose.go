package wizard

import (
	"regexp"
	"slices"
	"strings"

	"cachepanel/depmap"
	"cachepanel/recipe"
)

const skipDependencyCheck = "--skip-dependency-check"

// Fix is one automatic correction.
type Fix struct {
	Text  string
	apply func(*recipe.Spec)
}

// wanted is a dependency the log names.
type wanted struct {
	need   depmap.Need
	native bool
}

var (
	hashMismatch = regexp.MustCompile(`specified:\s+(sha256-[A-Za-z0-9+/=]+)\s+got:\s+(sha256-[A-Za-z0-9+/=]+)`)
	goVendored   = regexp.MustCompile(`vendor folder exists, please set 'vendorHash = null;'`)
	noLockfile   = regexp.MustCompile(`(?i)package-lock\.json.*(?:not found|does not exist|missing)|ERROR: The package-lock\.json file does not exist`)
	oldCMake     = regexp.MustCompile(`Compatibility with CMake < 3\.5 has been removed`)
	rustTooOld   = regexp.MustCompile(`rustc ([0-9.]+) is not supported by the following packages`)
	lockDrift    = regexp.MustCompile(`can only install packages when your package\.json and package-lock\.json`)
	pypaMissing  = regexp.MustCompile(`ERROR Missing dependencies:`)
	unknownHook  = regexp.MustCompile(`Unknown build hook: (\S+)`)
	badObject    = regexp.MustCompile(`fatal: bad object [0-9a-f]{7,}`)
	missingRules = []struct {
		pattern *regexp.Regexp
		lookup  func(string) depmap.Need
		native  bool
	}{
		{regexp.MustCompile(`could not satisfy dependency (\S+) wanted by`), depmap.Soname, false},
		{regexp.MustCompile(`ERROR: Dependency "([^"]+)" not found`), depmap.PkgConfig, false},
		{regexp.MustCompile(`No package '([^']+)' found`), depmap.PkgConfig, false},
		{regexp.MustCompile(`Package '([^']+)', required by '[^']*', not found`), depmap.PkgConfig, false},
		{regexp.MustCompile(`Package ([A-Za-z0-9_.+-]+) was not found in the pkg-config search path`), depmap.PkgConfig, false},
		{regexp.MustCompile("The system library `([^`]+)` required by crate"), depmap.PkgConfig, false},
		{regexp.MustCompile(`provided by "([A-Za-z0-9_]+)"`), depmap.CMake, false},
		{regexp.MustCompile(`Could NOT find ([A-Za-z0-9_]+)`), depmap.CMake, false},
		{regexp.MustCompile(`fatal error: ([A-Za-z0-9_./+-]+\.h): No such file or directory`), depmap.Header, false},
		{regexp.MustCompile(`([A-Za-z0-9_.+-]+): command not found`), depmap.Command, true},
		{regexp.MustCompile(`Program '([^']+)' not found or not executable`), depmap.Command, true},
		{regexp.MustCompile(`/bin/sh: [0-9]*:? ?([A-Za-z0-9_.+-]+): not found`), depmap.Command, true},
		{regexp.MustCompile(`env: '([A-Za-z0-9_.+-]+)': No such file or directory`), depmap.Command, true},
		{regexp.MustCompile(`failed to execute [^']*'([A-Za-z0-9_.+-]+)'`), depmap.Command, true},
		{regexp.MustCompile(`No module named '([A-Za-z0-9_]+)`), depmap.Python, true},
		{regexp.MustCompile(`- ([A-Za-z0-9_.-]+) not installed`), depmap.Python, false},
		{regexp.MustCompile(`make: ([A-Za-z0-9_.+-]+): No such file or directory`), depmap.Command, true},
		{regexp.MustCompile(`Backend '([A-Za-z0-9_.]+)' is not available`), depmap.PythonBackend, true},
	}
)

// hashFix updates the mismatched hash field.
func hashFix(log string, spec recipe.Spec) []Fix {
	match := hashMismatch.FindStringSubmatch(log)
	if match == nil {
		return nil
	}
	specified, got := match[1], match[2]
	for i, source := range spec.Sources {
		if source.Hash == specified || source.Hash == "" && recipe.Placeholder(i+1) == specified {
			return []Fix{{Text: "Found the checksum of source " + firstOf(source.Name, source.Repo, source.URL), apply: func(s *recipe.Spec) { s.Sources[i].Hash = got }}}
		}
	}
	if spec.VendorHash == specified || spec.VendorHash == "" && recipe.Placeholder(recipe.VendorSlot) == specified {
		return []Fix{{Text: "Found the checksum of the downloaded dependencies", apply: func(s *recipe.Spec) { s.VendorHash = got }}}
	}
	return nil
}

// layoutFixes handle vendoring surprises.
func layoutFixes(log string, spec recipe.Spec) []Fix {
	if pypaMissing.MatchString(log) && spec.Builder == recipe.Python && !slices.Contains(spec.Flags, skipDependencyCheck) {
		return []Fix{{Text: "The build system asks for versions nixpkgs lacks; building without that check", apply: func(s *recipe.Spec) { s.Flags = appendNew(s.Flags, skipDependencyCheck) }}}
	}
	if goVendored.MatchString(log) && !spec.Vendored {
		return []Fix{{Text: "The source ships vendor/; using it", apply: func(s *recipe.Spec) { s.Vendored, s.VendorHash = true, "" }}}
	}
	if oldCMake.MatchString(log) && spec.Builder == recipe.CMake {
		return []Fix{{Text: "Building with CMake compatibility for older projects", apply: func(s *recipe.Spec) { s.Flags = appendNew(s.Flags, "-DCMAKE_POLICY_VERSION_MINIMUM=3.5") }}}
	}
	if noLockfile.MatchString(log) && spec.Vendor == recipe.NpmVendor {
		return []Fix{{Text: "The source has no package-lock.json; building without the npm cache", apply: func(s *recipe.Spec) { s.Vendor, s.VendorHash = recipe.NoVendor, "" }}}
	}
	return nil
}

// missing lists logged dependencies, deduplicated.
func missing(log string) []wanted {
	var found []wanted
	seen := map[string]bool{}
	for _, rule := range missingRules {
		for _, match := range rule.pattern.FindAllStringSubmatch(log, -1) {
			if seen[match[1]] {
				continue
			}
			seen[match[1]] = true
			found = append(found, wanted{need: rule.lookup(match[1]), native: rule.native})
		}
	}
	return found
}

// dependencyFixes adds each missing attr once.
func dependencyFixes(spec recipe.Spec, wants []wanted, results []depmap.Result) ([]Fix, []string) {
	var hints []string
	var order []string
	reasons := map[string][]string{}
	native := map[string]bool{}
	for i, result := range results {
		if result.Missing || len(result.Attrs) == 0 {
			hints = append(hints, "The build lacks "+result.Name+", and no nixpkgs package fits automatically")
			continue
		}
		fresh := slices.DeleteFunc(slices.Clone(result.Attrs), func(attr string) bool { return present(spec, attr) })
		if len(fresh) == 0 {
			hints = append(hints, "The build lacks "+result.Name+" even though "+strings.Join(result.Attrs, ", ")+" is included")
			continue
		}
		for _, attr := range fresh {
			if reasons[attr] == nil {
				order = append(order, attr)
			}
			reasons[attr] = appendNew(reasons[attr], result.Name)
			native[attr] = native[attr] || wants[i].native
		}
	}
	fixes := make([]Fix, len(order))
	for i, attr := range order {
		fixes[i] = Fix{Text: "Added " + attr + " for " + strings.Join(reasons[attr], ", "), apply: func(s *recipe.Spec) {
			addDependency(s, []string{attr}, native[attr])
		}}
	}
	return fixes, hints
}

func addDependency(s *recipe.Spec, attrs []string, native bool) {
	for _, attr := range attrs {
		switch {
		case strings.HasPrefix(attr, "python3Packages.") && s.Builder == recipe.Python && native:
			s.BuildSystem = appendNew(s.BuildSystem, attr)
		case strings.HasPrefix(attr, "python3Packages.") && s.Builder == recipe.Python:
			s.PythonDeps = appendNew(s.PythonDeps, attr)
		case native:
			s.Native = appendNew(s.Native, attr)
		default:
			s.Inputs = appendNew(s.Inputs, attr)
		}
	}
}

func present(spec recipe.Spec, attr string) bool {
	for _, list := range [][]string{spec.Native, spec.Inputs, spec.Depends, spec.PythonDeps, spec.BuildSystem} {
		if slices.Contains(list, attr) {
			return true
		}
	}
	return false
}

// knownLimits explains unfixable failures.
func knownLimits(log string) []string {
	var hints []string
	if match := rustTooOld.FindStringSubmatch(log); match != nil {
		hints = append(hints, "The source needs a newer Rust than nixpkgs stable's "+match[1]+"; choose an older version")
	}
	if match := unknownHook.FindStringSubmatch(log); match != nil {
		hints = append(hints, "The source uses the build hook "+match[1]+", which nixpkgs lacks")
	}
	if badObject.MatchString(log) {
		hints = append(hints, "The PKGBUILD fetches git commits missing from the source history")
	}
	if lockDrift.MatchString(log) {
		hints = append(hints, "package-lock.json is out of sync with package.json in the source; choose another version")
	}
	return hints
}

// Zig releases, newest first.
var zigReleases = []string{"zig", "zig_0_15", "zig_0_14", "zig_0_13"}

var zigBroken = regexp.MustCompile(`compile (?:exe|lib|obj) \S+ \S+ .*\d+ errors?`)

// toolchainFixes steps back one Zig release.
func toolchainFixes(log string, spec recipe.Spec) []Fix {
	if !zigBroken.MatchString(log) {
		return nil
	}
	for i, release := range zigReleases[:len(zigReleases)-1] {
		older := zigReleases[i+1]
		if !slices.Contains(spec.Native, release) {
			continue
		}
		return []Fix{{Text: "The source does not fit " + release + "; trying " + older, apply: func(s *recipe.Spec) {
			s.Native[slices.Index(s.Native, release)] = older
		}}}
	}
	return nil
}
