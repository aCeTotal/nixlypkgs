package profiles

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"cachepanel/source"
)

const profilesDir = "nixlyos/profiles"

// Profile is one nixlyos/profiles/<name>.json.
type Profile struct {
	Title          string            `json:"title"`
	Description    string            `json:"description"`
	Platform       string            `json:"platform"`
	Kernel         string            `json:"kernel"`
	KernelSettings map[string]string `json:"kernelSettings"`
	PinnedSha      *string           `json:"pinnedSha"`
	// Modules are chosen optional ones.
	Modules  []string `json:"modules"`
	Packages []string `json:"packages"`
}

func profilePath(name string) string {
	return profilesDir + "/" + name + ".json"
}

func (p Profile) validate(name string) error {
	switch {
	case !namePattern.MatchString(name):
		return errName
	case len(p.Title) == 0 || len([]rune(p.Title)) > 80:
		return errTitle
	case !platforms[p.Platform]:
		return errPlatform
	}
	for _, pkg := range p.Packages {
		if !attrPattern.MatchString(pkg) {
			return errPackage
		}
	}
	return nil
}

// normalized is the stored form.
func (p Profile) normalized() Profile {
	p.Modules = uniq(p.Modules)
	slices.Sort(p.Modules)
	p.Packages = uniq(p.Packages)
	if p.KernelSettings == nil {
		p.KernelSettings = map[string]string{}
	}
	return p
}

func (p Profile) encode() (string, error) {
	var b strings.Builder
	encoder := json.NewEncoder(&b)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	err := encoder.Encode(p.normalized())
	return b.String(), err
}

func decodeProfile(name, text string) (Profile, error) {
	var profile Profile
	if err := json.Unmarshal([]byte(text), &profile); err != nil {
		return Profile{}, fmt.Errorf("%s: %w", profilePath(name), err)
	}
	if err := profile.validate(name); err != nil {
		return Profile{}, fmt.Errorf("%s: %w", profilePath(name), err)
	}
	return profile.normalized(), nil
}

// profilesAt reads profiles at rev.
func profilesAt(ctx context.Context, repo *source.Repo, rev string) (map[string]Profile, error) {
	files, err := repo.FolderAt(ctx, rev, profilesDir)
	if err != nil {
		return nil, err
	}
	kept := make(map[string]Profile, len(files))
	for path, text := range files {
		name, found := strings.CutSuffix(strings.TrimPrefix(path, profilesDir+"/"), ".json")
		if !found {
			continue
		}
		profile, err := decodeProfile(name, text)
		if err != nil {
			return nil, err
		}
		kept[name] = profile
	}
	return kept, nil
}

// ModuleUsed checks imports at rev.
func (b *Rebuilder) ModuleUsed(ctx context.Context, rev, slug string) (bool, error) {
	kept, err := profilesAt(ctx, b.Source, rev)
	if err != nil {
		return false, err
	}
	for _, profile := range kept {
		if slices.Contains(profile.Modules, slug) {
			return true, nil
		}
	}
	return false, nil
}
