package profiles

import (
	"context"
	"errors"
	"net/http"
	"reflect"
	"regexp"

	"github.com/go-chi/chi/v5"

	"cachepanel/modules"
	"cachepanel/realtime"
	"cachepanel/rest"
	"cachepanel/source"
)

// New profiles start on this kernel.
const defaultKernel = "performance"

var (
	namePattern  = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)
	attrPattern  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*(\.[A-Za-z_][A-Za-z0-9_'-]*)*$`)
	platforms    = map[string]bool{"desktop": true, "htpc": true, "server": true}
	errName      = rest.Unprocessable("invalid_name", "The ID may only contain lowercase letters, digits and hyphens (max 32)")
	errTitle     = rest.Unprocessable("invalid_title", "The name needs 1–80 characters")
	errPlatform  = rest.Unprocessable("invalid_platform", "Unknown platform")
	errPackage   = rest.Unprocessable("invalid_package", "Invalid package – use e.g. blender or python3Packages.numpy")
	errPinnedRev = rest.Unprocessable("invalid_revision", "That revision is not evaluated")
	errExists    = rest.Conflict("profile_exists", "A profile already has that ID")
	errLast      = rest.Conflict("last_profile", "Keep at least one profile")
)

// Routes commit profile edits.
type Routes struct {
	*Rebuilder
	// Poke starts evaluating a new commit.
	Poke func()
}

// change carries base and message.
type change struct {
	Base    string `json:"base"`
	Message string `json:"message"`
}

// draft is a full profile edit.
type draft struct {
	Name string `json:"name"`
	Profile
	change
}

func (p *Routes) create(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Name        string `json:"name"`
		Title       string `json:"title"`
		Description string `json:"description"`
		Platform    string `json:"platform"`
		change
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	profile := Profile{Title: req.Title, Description: req.Description, Platform: req.Platform, Kernel: defaultKernel,
		Modules: []string{}, Packages: []string{}}
	if err := profile.validate(req.Name); err != nil {
		return err
	}
	return p.add(w, r, req.change, req.Name, profile)
}

func (p *Routes) clone(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Name  string `json:"name"`
		Title string `json:"title"`
		change
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	profile, err := p.profileAt(r.Context(), req.Base, chi.URLParam(r, "name"))
	if err != nil {
		return err
	}
	profile.Title = req.Title
	if err := profile.validate(req.Name); err != nil {
		return err
	}
	return p.add(w, r, req.change, req.Name, profile)
}

// add writes a new profile.
func (p *Routes) add(w http.ResponseWriter, r *http.Request, req change, name string, profile Profile) error {
	if err := p.free(r.Context(), req.Base, name); err != nil {
		return err
	}
	text, err := profile.encode()
	if err != nil {
		return err
	}
	edit := source.Edit{Base: req.Base, Message: req.Message, Changes: []source.FileChange{{Path: profilePath(name), Content: &text}}}
	return p.committed(w, r, edit, name)
}

func (p *Routes) update(w http.ResponseWriter, r *http.Request) error {
	var req draft
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := req.validate(req.Name); err != nil {
		return err
	}
	current := chi.URLParam(r, "name")
	before, err := p.profileAt(r.Context(), req.Base, current)
	if err != nil {
		return err
	}
	profile, err := p.settle(r.Context(), req.Base, req.Profile)
	if err != nil {
		return err
	}
	// Formatting alone is no change.
	if req.Name == current && reflect.DeepEqual(profile.normalized(), before) {
		return source.ErrUnchanged
	}
	text, err := profile.encode()
	if err != nil {
		return err
	}
	changes := []source.FileChange{{Path: profilePath(req.Name), Content: &text}}
	if req.Name != current {
		if err := p.free(r.Context(), req.Base, req.Name); err != nil {
			return err
		}
		changes = append(changes, source.FileChange{Path: profilePath(current)})
	}
	return p.committed(w, r, source.Edit{Base: req.Base, Message: req.Message, Changes: changes}, req.Name)
}

// settle checks choices against catalogues.
func (p *Routes) settle(ctx context.Context, base string, profile Profile) (Profile, error) {
	entries, err := modules.Catalogue(ctx, p.Source, base)
	if err != nil {
		return Profile{}, err
	}
	if err := checkModules(entries, profile.Modules); err != nil {
		return Profile{}, err
	}
	if profile.PinnedSha != nil {
		var done bool
		err := p.DB.QueryRow(ctx, `SELECT eval_state = 'done' FROM commits WHERE sha = $1`, *profile.PinnedSha).Scan(&done)
		if err != nil || !done {
			return Profile{}, errPinnedRev
		}
	}
	profile.KernelSettings, err = chooseKernel(ctx, p.DB, profile)
	return profile, err
}

func (p *Routes) remove(w http.ResponseWriter, r *http.Request) error {
	var req change
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	name := chi.URLParam(r, "name")
	kept, err := profilesAt(r.Context(), p.Source, req.Base)
	if err != nil {
		return err
	}
	if _, found := kept[name]; !found {
		return rest.NotFound()
	}
	if len(kept) == 1 {
		return errLast
	}
	edit := source.Edit{Base: req.Base, Message: req.Message, Changes: []source.FileChange{{Path: profilePath(name)}}}
	return p.committed(w, r, edit, name)
}

// free refuses taken names.
func (p *Routes) free(ctx context.Context, rev, name string) error {
	_, err := p.Source.FileAt(ctx, rev, profilePath(name))
	if err == nil {
		return errExists
	}
	if errors.Is(err, source.ErrNoFile) {
		return nil
	}
	return err
}

func (p *Routes) profileAt(ctx context.Context, rev, name string) (Profile, error) {
	blob, err := p.Source.FileAt(ctx, rev, profilePath(name))
	if err != nil {
		return Profile{}, err
	}
	return decodeProfile(name, blob.Text)
}

func (p *Routes) committed(w http.ResponseWriter, r *http.Request, edit source.Edit, name string) error {
	sha, err := p.Source.Commit(r.Context(), edit, p.Source.Author(r))
	if err != nil {
		return err
	}
	p.Poke()
	p.Hub.Publish(realtime.ProfileChanged, map[string]string{"name": name})
	p.Hub.Publish(realtime.SourceChanged, map[string]string{"sha": sha})
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"sha": sha, "name": name})
}

// uniq keeps first occurrences.
func uniq(values []string) []string {
	seen := map[string]bool{}
	kept := []string{}
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			kept = append(kept, value)
		}
	}
	return kept
}
