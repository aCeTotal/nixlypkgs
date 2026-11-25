package recipe

import (
	"encoding/json"
	"os/exec"
	"strings"
	"testing"

	"cachepanel/upstream"
)

const commit = "1111111111111111111111111111111111111111"

func TestTrackedSourcesPinThroughSourceJSON(t *testing.T) {
	if _, err := exec.LookPath("nixfmt"); err != nil {
		t.Skip("nixfmt missing")
	}
	prefix := "v"
	spec := sample(Cargo)
	spec.Sources = []Source{{Kind: GitHub, Owner: "o", Repo: "demo", Rev: "v1.2.0", Commit: commit, Tags: &prefix}}
	files, err := Files(t.Context(), spec)
	if err != nil {
		t.Fatal(err)
	}
	nix := string(files["default.nix"])
	for _, want := range []string{"source = lib.importJSON ./source.json", "inherit (source) version;", "inherit (source) rev hash;", "inherit (source) cargoHash;"} {
		if !strings.Contains(nix, want) {
			t.Errorf("default.nix lacks %q:\n%s", want, nix)
		}
	}
	var pinned upstream.Source
	if err := json.Unmarshal(files[upstreamFile], &pinned); err != nil {
		t.Fatal(err)
	}
	if pinned.URL != "https://github.com/o/demo" || pinned.Rev != commit || *pinned.Tags != "v" || pinned.Version != "1.2.0" ||
		pinned.Hash != Placeholder(1) || pinned.CargoHash != Placeholder(VendorSlot) {
		t.Fatalf("source.json = %+v", pinned)
	}
}

func TestUntrackedSourcesStayInline(t *testing.T) {
	if _, err := exec.LookPath("nixfmt"); err != nil {
		t.Skip("nixfmt missing")
	}
	spec := sample(Cargo)
	spec.Sources = []Source{{Kind: GitHub, Owner: "o", Repo: "demo", Rev: commit, Hash: "sha256-x"}}
	files, err := Files(t.Context(), spec)
	if err != nil {
		t.Fatal(err)
	}
	if _, found := files[upstreamFile]; found || strings.Contains(string(files["default.nix"]), "source.json") {
		t.Fatalf("pinned without a branch or tags: %v", files)
	}
}
