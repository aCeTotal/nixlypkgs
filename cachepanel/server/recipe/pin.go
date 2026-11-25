package recipe

import (
	"context"

	"cachepanel/upstream"
)

// upstreamFile is what the tracker keeps current.
const upstreamFile = "source.json"

// tracked is a lone GitHub source that follows upstream.
func tracked(s Spec) bool {
	if len(s.Sources) != 1 {
		return false
	}
	src := s.Sources[0]
	return src.Kind == GitHub && !src.History && (src.Branch != "" || src.Tags != nil)
}

// pin is the source.json the tracker keeps current.
func pin(s Spec) upstream.Source {
	src := s.Sources[0]
	pinned := upstream.Source{URL: "https://github.com/" + src.Owner + "/" + src.Repo, Branch: src.Branch, Tags: src.Tags,
		Rev: src.Rev, Hash: hashOr(src.Hash, 1), Version: s.Version}
	if src.Commit != "" {
		pinned.Rev = src.Commit
	}
	vendored := hashOr(s.VendorHash, VendorSlot)
	switch {
	case s.Builder == Cargo:
		pinned.CargoHash = vendored
	case s.Builder == Go && !s.Vendored:
		pinned.VendorHash = vendored
	case s.Builder == Npm:
		pinned.NpmDepsHash = vendored
	}
	return pinned
}

// Files renders default.nix, and source.json when tracked.
func Files(ctx context.Context, s Spec) (map[string][]byte, error) {
	text, err := Render(s)
	if err == nil {
		text, err = Format(ctx, text)
	}
	if err != nil {
		return nil, err
	}
	files := map[string][]byte{"default.nix": []byte(text)}
	if !tracked(s) {
		return files, nil
	}
	pinned, err := pin(s).Encode()
	files[upstreamFile] = []byte(pinned)
	return files, err
}
