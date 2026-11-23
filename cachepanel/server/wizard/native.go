package wizard

import (
	"context"
	"fmt"
	"path"
	"regexp"
	"strings"

	"cachepanel/analyse"
	"cachepanel/depmap"
	"cachepanel/pkgbuild"
	"cachepanel/recipe"
)

var (
	tagVersion = regexp.MustCompile(`^(?:[A-Za-z_-]*?)v?([0-9]+(?:\.[0-9]+)*.*)$`)
)

func (l *Lab) fromURL(ctx context.Context, flake, url string) (Draft, error) {
	name := pkgbuild.StoreName(path.Base(strings.SplitN(url, "?", 2)[0]))
	fetched, err := analyse.File(ctx, url, name)
	if err != nil {
		return Draft{}, err
	}
	return l.fromFile(ctx, flake, recipe.Source{Kind: recipe.URL, URL: url, Name: name, Hash: fetched.Hash}, fetched)
}

func (l *Lab) fromUpload(ctx context.Context, flake, hash string) (Draft, error) {
	url, err := l.Uploads.URL(hash)
	if err != nil {
		return Draft{}, err
	}
	fetched, err := l.Uploads.Seed(ctx, hash)
	if err != nil {
		return Draft{}, err
	}
	return l.fromFile(ctx, flake, recipe.Source{Kind: recipe.Upload, URL: url, Name: path.Base(url), Hash: fetched.Hash}, fetched)
}

// fromFile analyses a file by content.
func (l *Lab) fromFile(ctx context.Context, flake string, source recipe.Source, fetched analyse.Fetched) (Draft, error) {
	kind, err := analyse.KindOf(fetched.Path, source.Name)
	if err != nil {
		return Draft{}, err
	}
	pname := guessName(source.Name)
	spec := recipe.Spec{Attr: pname, Pname: pname, Version: guessVersion(source.URL, source.Name), Sources: []recipe.Source{source}}
	switch kind {
	case analyse.Executable:
		spec.Builder, spec.Layout = recipe.Prebuilt, recipe.Layout{Mode: recipe.FileLayout}
		spec.Meta.MainProgram = pname
		return Draft{Spec: spec}, nil
	case analyse.Unknown:
		return Draft{}, fmt.Errorf("unrecognised file type of %s", source.Name)
	}
	tree, err := analyse.Unpack(ctx, flake, fetched.Path, kind)
	if err != nil {
		return Draft{}, err
	}
	switch kind {
	case analyse.AppImageFile:
		spec.Builder, spec.Layout = recipe.AppImage, analyse.AppImage(tree, pname)
		spec.Meta.MainProgram = pname
		return Draft{Spec: spec}, nil
	case analyse.DebPackage, analyse.RpmPackage:
		return packageDraft(spec, kind, tree), nil
	}
	facts, err := analyse.Archive(tree, pname)
	if err != nil {
		return Draft{}, err
	}
	return fromFacts(ctx, flake, spec, facts, facts.Top)
}

func packageDraft(spec recipe.Spec, kind analyse.Kind, tree string) Draft {
	spec.Builder, spec.Layout, spec.NoStrip = recipe.Rpm, analyse.Packages(tree, spec.Pname), true
	if kind == analyse.DebPackage {
		control := analyse.Control(tree)
		spec.Builder = recipe.Deb
		spec.Pname = firstOf(control["Package"], spec.Pname)
		spec.Attr = attrName(spec.Pname)
		spec.Version = firstOf(versionOnly(control["Version"]), spec.Version)
		spec.Meta.Description, spec.Meta.Homepage = control["Description"], control["Homepage"]
	}
	if len(spec.Layout.Programs) == 1 {
		spec.Meta.MainProgram = spec.Layout.Programs[0].Name
	}
	return Draft{Spec: spec}
}

func (l *Lab) fromGitHub(ctx context.Context, flake, owner, repo, ref string) (Draft, error) {
	about := gitHubAbout(ctx, owner, repo)
	ref = firstOf(ref, about.Release)
	fetched, err := analyse.Repository(ctx, "github:"+owner+"/"+repo+suffix("/", ref))
	if err != nil {
		return Draft{}, err
	}
	source := recipe.Source{Kind: recipe.GitHub, Owner: owner, Repo: repo, Rev: fetched.Rev, Hash: fetched.Hash}
	version := dateVersion(fetched.Modified)
	if match := tagVersion.FindStringSubmatch(ref); match != nil && ref != fetched.Rev {
		source.Rev, version = ref, match[1]
	}
	pname := attrName(strings.ToLower(repo))
	spec := recipe.Spec{Attr: pname, Pname: pname, Version: version, Sources: []recipe.Source{source},
		Meta: recipe.Meta{Description: about.Description, Homepage: firstOf(about.Homepage, "https://github.com/"+owner+"/"+repo), License: recipe.License(about.License)}}
	facts, err := analyse.Tree(fetched.Path, pname)
	if err != nil {
		return Draft{}, err
	}
	if named := attrName(strings.ToLower(facts.Name)); facts.Name != "" && !strings.HasPrefix(named, "pkg-") {
		spec.Pname, spec.Attr = named, named
	}
	return fromFacts(ctx, flake, spec, facts, "source")
}

// fromFacts fills a spec from analysis.
func fromFacts(ctx context.Context, flake string, spec recipe.Spec, facts analyse.Facts, top string) (Draft, error) {
	spec.Builder, spec.Layout, spec.Vendored, spec.NoBuild = facts.Builder, facts.Layout, facts.Vendored, facts.NoBuild
	if facts.Sub != "" {
		spec.Root = top + "/" + facts.Sub
	}
	if facts.Version != "" && spec.Version == "0" {
		spec.Version = facts.Version
	}
	spec.Meta.Description = firstOf(spec.Meta.Description, facts.Description)
	spec.Meta.Homepage = firstOf(spec.Meta.Homepage, facts.Homepage)
	spec.Meta.License = firstOf(spec.Meta.License, recipe.License(facts.License))
	if spec.Builder == recipe.Make {
		spec.Flags = []string{"PREFIX=$(out)"}
	}
	if spec.Builder == recipe.Prebuilt {
		spec.NoStrip = true
	}
	draft := Draft{}
	groups := [][]depmap.Need{facts.Needs, facts.Python, facts.BuildSystem}
	results, err := depmap.Resolve(ctx, flake, append(append(facts.Needs, facts.Python...), facts.BuildSystem...))
	if err != nil {
		return Draft{}, err
	}
	targets := []*[]string{&spec.Inputs, &spec.PythonDeps, &spec.BuildSystem}
	offset := 0
	for group, needs := range groups {
		for _, result := range results[offset : offset+len(needs)] {
			draft.noteMissing(result)
			*targets[group] = appendNew(*targets[group], result.Attrs...)
		}
		offset += len(needs)
	}
	spec.Native = appendNew(facts.Tools, guiHooks(spec.Inputs)...)
	draft.Spec = spec
	return draft, nil
}

// versionOnly drops Debian epochs and revisions.
func versionOnly(version string) string {
	if _, rest, ok := strings.Cut(version, ":"); ok {
		version = rest
	}
	version, _, _ = strings.Cut(version, "-")
	return version
}
