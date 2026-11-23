package wizard

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"cachepanel/analyse"
	"cachepanel/depmap"
	"cachepanel/pkgbuild"
	"cachepanel/recipe"
)

// Toolchains whose dependencies makepkg would download.
var vendors = map[string]recipe.Vendor{
	"cargo": recipe.CargoVendor, "rust": recipe.CargoVendor, "rustup": recipe.CargoVendor,
	"go": recipe.GoVendor, "npm": recipe.NpmVendor, "nodejs": recipe.NpmVendor,
}

var binarySuffixes = []string{".deb", ".rpm", ".AppImage", ".appimage"}

var commitHash = regexp.MustCompile(`^[0-9a-f]{40}$`)

// Git-history readers need full clones.
var gitHistory = regexp.MustCompile(`\bgit\s+(?:-C\s+\S+\s+)?(?:show|log|rev-list|describe|apply|am|cherry-pick|revert|submodule)\b`)

func (l *Lab) fromRepository(ctx context.Context, flake string, origin Origin, name string) (Draft, error) {
	files, err := pkgbuild.Fetch(ctx, pkgbuild.Origin(origin), name)
	if err != nil {
		return Draft{}, fmt.Errorf("fetch %s: %w", name, err)
	}
	return l.fromPkgbuild(ctx, flake, files, name)
}

// fromPkgbuild picks split want, else first.
func (l *Lab) fromPkgbuild(ctx context.Context, flake string, files map[string][]byte, want string) (Draft, error) {
	if files["PKGBUILD"] == nil {
		return Draft{}, fmt.Errorf("no PKGBUILD found")
	}
	dir, err := os.MkdirTemp("", "pkgbuild-")
	if err != nil {
		return Draft{}, err
	}
	defer func() { _ = os.RemoveAll(dir) }()
	for name, content := range files {
		if !uploadPattern.MatchString(name) {
			return Draft{}, errFileName
		}
		if err := os.WriteFile(filepath.Join(dir, name), content, 0o600); err != nil {
			return Draft{}, err
		}
	}
	info, err := pkgbuild.Read(ctx, flake, dir)
	if err != nil {
		return Draft{}, err
	}
	draft := Draft{Files: map[string][]byte{"PKGBUILD": files["PKGBUILD"]}}
	spec := recipe.Spec{
		Attr: attrName(info.Names[0]), Pname: info.Names[0], Version: info.Version, Builder: recipe.Makepkg,
		NoExtract: info.NoExtract, NoStrip: info.Option("!strip"),
		Meta: recipe.Meta{Description: info.Description, Homepage: info.URL},
	}
	if len(info.Licenses) > 0 {
		spec.Meta.License = recipe.License(info.Licenses[0])
	}
	if splits := info.Splits(); len(splits) > 0 {
		spec.Split = splits[0]
		if slices.Contains(splits, want) {
			spec.Split = want
		}
		spec.Pname, spec.Attr = spec.Split, attrName(spec.Split)
	}
	if err := l.archSources(ctx, info, files, &spec, &draft); err != nil {
		return Draft{}, err
	}
	if err := archDependencies(ctx, flake, info, &spec, &draft); err != nil {
		return Draft{}, err
	}
	if image, ok := l.lonelyAppImage(ctx, flake, spec); ok {
		spec = image
		draft.Files = nil
	}
	draft.Spec = spec
	return draft, nil
}

func (l *Lab) archSources(ctx context.Context, info pkgbuild.Info, files map[string][]byte, spec *recipe.Spec, draft *Draft) error {
	for _, line := range info.Sources {
		entry, err := pkgbuild.ParseEntry(line)
		if err != nil {
			return err
		}
		if entry.Local {
			if files[entry.Name] == nil {
				return fmt.Errorf("the PKGBUILD references %s, which is missing", entry.Name)
			}
			draft.Files[entry.Name] = files[entry.Name]
			spec.Sources = append(spec.Sources, recipe.Source{Kind: recipe.File, Name: entry.Name})
			continue
		}
		source, fetched, err := fetchEntry(ctx, entry)
		if err != nil {
			return err
		}
		source.History = entry.Git && gitHistory.Match(files["PKGBUILD"])
		spec.Sources = append(spec.Sources, source)
		if info.Has("pkgver") && !fetched.Modified.IsZero() {
			spec.Version = dateVersion(fetched.Modified)
			draft.Notes = append(draft.Notes, "The git source is pinned to "+fetched.Rev[:12]+"; the version is the commit date")
		}
	}
	return nil
}

// fetchEntry locks one makepkg source.
func fetchEntry(ctx context.Context, entry pkgbuild.Entry) (recipe.Source, analyse.Fetched, error) {
	if !entry.Git {
		fetched, err := analyse.File(ctx, entry.URL, entry.Name)
		return recipe.Source{Kind: recipe.URL, Name: entry.Name, URL: entry.URL, Hash: fetched.Hash}, fetched, err
	}
	ref := firstOf(entry.Rev, entry.Branch)
	if match := githubRepo.FindStringSubmatch(entry.URL); match != nil {
		fetched, err := analyse.Repository(ctx, "github:"+match[1]+"/"+match[2]+suffix("/", ref))
		return recipe.Source{Kind: recipe.GitHub, Name: entry.Name, Owner: match[1], Repo: match[2], Rev: firstOf(entry.Rev, fetched.Rev), Hash: fetched.Hash}, fetched, err
	}
	query := suffix("?ref=", entry.Branch) + suffix("?ref=refs/tags/", entry.Rev)
	if commitHash.MatchString(entry.Rev) {
		query = "?rev=" + entry.Rev
	}
	fetched, err := analyse.Repository(ctx, "git+"+entry.URL+query)
	return recipe.Source{Kind: recipe.Git, Name: entry.Name, URL: entry.URL, Rev: fetched.Rev, Hash: fetched.Hash}, fetched, err
}

func archDependencies(ctx context.Context, flake string, info pkgbuild.Info, spec *recipe.Spec, draft *Draft) error {
	runtime := needsOf(info.Depends, depmap.Arch)
	build := needsOf(info.MakeDepends, depmap.Arch)
	results, err := depmap.Resolve(ctx, flake, append(runtime, build...))
	if err != nil {
		return err
	}
	for i, result := range results {
		draft.noteMissing(result)
		for _, attr := range result.Attrs {
			switch {
			case i >= len(runtime):
				spec.Native = appendNew(spec.Native, attr)
			case strings.HasPrefix(attr, "python3Packages."):
				spec.PythonDeps = appendNew(spec.PythonDeps, attr)
			default:
				spec.Depends = appendNew(spec.Depends, attr)
			}
		}
	}
	for _, dep := range info.MakeDepends {
		if vendor, ok := vendors[depmap.Arch(dep).Name]; ok && (vendor != recipe.NpmVendor || spec.Vendor == recipe.NoVendor) {
			spec.Vendor = vendor
		}
	}
	if binaryPackage(info) {
		spec.Native = appendNew(spec.Native, "autoPatchelfHook")
	}
	spec.Native = appendNew(spec.Native, guiHooks(append(spec.Depends, spec.Native...))...)
	return nil
}

// binaryPackage repackages upstream builds.
func binaryPackage(info pkgbuild.Info) bool {
	if strings.HasSuffix(info.Names[0], "-bin") {
		return true
	}
	return slices.ContainsFunc(info.Sources, func(source string) bool {
		return slices.ContainsFunc(binarySuffixes, func(suffix string) bool { return strings.HasSuffix(source, suffix) })
	})
}

// lonelyAppImage prefers appimageTools for AppImages.
func (l *Lab) lonelyAppImage(ctx context.Context, flake string, spec recipe.Spec) (recipe.Spec, bool) {
	remote := slices.DeleteFunc(slices.Clone(spec.Sources), func(s recipe.Source) bool { return s.Kind == recipe.File })
	images := slices.DeleteFunc(slices.Clone(remote), func(s recipe.Source) bool {
		return s.Kind != recipe.URL || !strings.HasSuffix(strings.ToLower(s.Name), ".appimage")
	})
	if len(images) != 1 || len(remote) > 1 && !strings.Contains(spec.Pname, "appimage") {
		return spec, false
	}
	remote = images
	fetched, err := analyse.File(ctx, remote[0].URL, remote[0].Name)
	if err != nil {
		return spec, false
	}
	contents, err := analyse.Unpack(ctx, flake, fetched.Path, analyse.AppImageFile)
	if err != nil {
		return spec, false
	}
	image := spec
	image.Builder, image.Sources, image.Native, image.Depends, image.PythonDeps = recipe.AppImage, remote, nil, nil, nil
	image.Vendor, image.Split, image.NoExtract = recipe.NoVendor, "", nil
	image.Layout = analyse.AppImage(contents, spec.Pname)
	image.Meta.MainProgram = spec.Pname
	return image, true
}

func suffix(prefix, value string) string {
	if value == "" {
		return ""
	}
	return prefix + value
}
