package wizard

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"cachepanel/recipe"
)

// Origin is where an import starts.
type Origin string

const (
	FromAUR      Origin = "aur"
	FromArch     Origin = "arch"
	FromPkgbuild Origin = "pkgbuild"
	FromURL      Origin = "url"
	FromUpload   Origin = "upload"
	FromGitHub   Origin = "github"
)

// Request starts a recipe.
type Request struct {
	Origin Origin `json:"origin"`
	// Name is an AUR/Arch package.
	Name string `json:"name,omitempty"`
	URL  string `json:"url,omitempty"`
	// Ref is a tag, branch or commit.
	Ref string `json:"ref,omitempty"`
	// Upload is an uploaded file's sha256.
	Upload string `json:"upload,omitempty"`
	// Files hold an uploaded PKGBUILD tree.
	Files map[string][]byte `json:"files,omitempty"`
}

// Draft is a spec plus its files.
type Draft struct {
	Spec  recipe.Spec       `json:"spec"`
	Files map[string][]byte `json:"-"`
	Notes []string          `json:"notes"`
}

// Lab imports and test-builds recipes.
type Lab struct {
	// Flake names the package set's revision.
	Flake   func(context.Context) (string, error)
	Uploads *Uploads

	names names
}

var (
	githubRepo = regexp.MustCompile(`^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?(?:/(?:tree|releases/tag)/([^?#]+))?/?$`)
	invalidPid = regexp.MustCompile(`[^A-Za-z0-9_-]+`)
	errOrigin  = errors.New("ukjent importtype")
)

// ownSuffix keeps nixpkgs names free.
const ownSuffix = "-nixly"

// Import analyses; nixpkgs-owned attrs get suffixed.
func (l *Lab) Import(ctx context.Context, req Request) (Draft, error) {
	draft, err := l.analyse(ctx, req)
	if err != nil {
		return Draft{}, err
	}
	taken, err := l.Taken(ctx, draft.Spec.Attr)
	if taken {
		draft.Spec.Attr += ownSuffix
		draft.Notes = append(draft.Notes, "nixpkgs har allerede "+strings.TrimSuffix(draft.Spec.Attr, ownSuffix)+", så pakken heter "+draft.Spec.Attr+" her")
	}
	return draft, err
}

func (l *Lab) analyse(ctx context.Context, req Request) (Draft, error) {
	flake, err := l.Flake(ctx)
	if err != nil {
		return Draft{}, err
	}
	if req.Origin == FromURL {
		if match := githubRepo.FindStringSubmatch(req.URL); match != nil {
			return l.fromGitHub(ctx, flake, match[1], match[2], firstOf(req.Ref, match[3]))
		}
		return l.fromURL(ctx, flake, req.URL)
	}
	switch req.Origin {
	case FromAUR, FromArch:
		return l.fromRepository(ctx, flake, req.Origin, req.Name)
	case FromPkgbuild:
		return l.fromPkgbuild(ctx, flake, req.Files, "")
	case FromUpload:
		return l.fromUpload(ctx, flake, req.Upload)
	case FromGitHub:
		match := githubRepo.FindStringSubmatch(req.URL)
		if match == nil {
			return Draft{}, fmt.Errorf("%q er ikke et GitHub-repo", req.URL)
		}
		return l.fromGitHub(ctx, flake, match[1], match[2], firstOf(req.Ref, match[3]))
	}
	return Draft{}, errOrigin
}

// attrName sanitises a name into an attribute.
func attrName(name string) string {
	clean := strings.Trim(invalidPid.ReplaceAllString(name, "-"), "-")
	if clean == "" || clean[0] >= '0' && clean[0] <= '9' {
		clean = "pkg-" + clean
	}
	return clean
}

// dateVersion versions git-pinned packages.
func dateVersion(t time.Time) string {
	return t.Format("2006.01.02")
}

func firstOf(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
