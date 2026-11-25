package upstream

import (
	"errors"
	"strings"
	"testing"
)

const (
	oldRev = "1111111111111111111111111111111111111111"
	newRev = "2222222222222222222222222222222222222222"
)

func TestSourceValidates(t *testing.T) {
	prefix := "v"
	good := []Source{
		{URL: "https://github.com/aCeTotal/nixlytile", Branch: "main", Rev: oldRev, Hash: "sha256-x"},
		{URL: "file:///srv/demo.git", Tags: &prefix, Rev: oldRev, Hash: "sha256-x"},
	}
	for _, each := range good {
		if err := each.validate(); err != nil {
			t.Errorf("%+v: %v", each, err)
		}
	}
	bad := []Source{
		{URL: "--upload-pack=x", Branch: "main", Rev: oldRev, Hash: "sha256-x"},
		{URL: "https://example.com/r", Rev: oldRev, Hash: "sha256-x"},
		{URL: "https://example.com/r", Branch: "main", Tags: &prefix, Rev: oldRev, Hash: "sha256-x"},
		{URL: "https://example.com/r", Branch: "main", Rev: "-x", Hash: "sha256-x"},
	}
	for _, each := range bad {
		if err := each.validate(); !errors.Is(err, errSource) {
			t.Errorf("%+v passed", each)
		}
	}
}

func TestFlakeRefMatchesTheFetcher(t *testing.T) {
	cases := map[string]string{
		"https://github.com/aCeTotal/nixlytile":     "github:aCeTotal/nixlytile/" + newRev,
		"https://github.com/aCeTotal/nixlytile.git": "github:aCeTotal/nixlytile/" + newRev,
		"https://codeberg.org/someone/thing":        "git+https://codeberg.org/someone/thing?rev=" + newRev,
	}
	for url, want := range cases {
		if got := flakeRef(url, newRev); got != want {
			t.Errorf("%s = %s", url, got)
		}
	}
}

func TestReportedHashIsParsed(t *testing.T) {
	report := "error: hash mismatch in fixed-output derivation '/nix/store/x-vendor.drv':\n  specified: sha256-AAAA=\n     got:    sha256-q5JkD+qaso3sG31kzx/JfEwiMJmRTYSezh1POnmmA04=\n"
	if match := gotHash.FindStringSubmatch(report); match == nil || match[1] != "sha256-q5JkD+qaso3sG31kzx/JfEwiMJmRTYSezh1POnmmA04=" {
		t.Fatalf("match = %q", match)
	}
}

func TestClassifyWaitsOnFailedRevisions(t *testing.T) {
	sources := map[string]Source{"a": {Rev: oldRev}, "b": {Rev: oldRev}, "c": {Rev: oldRev}, "d": {Rev: oldRev}}
	probes := []probe{
		{attr: "a", latest: Latest{Rev: oldRev}},
		{attr: "b", latest: Latest{Rev: newRev, Version: "2026.11.25"}},
		{attr: "c", latest: Latest{Rev: newRev}},
		{attr: "d", err: errors.New("unreachable")},
	}
	known := map[string]seen{"c": {LatestRev: newRev, State: stateFailed, Error: "cargo failed"}}
	outcomes, behind := classify(probes, sources, known)
	if len(behind) != 1 || behind[0].attr != "b" || behind[0].next.Rev != newRev || behind[0].next.Version != "2026.11.25" {
		t.Fatalf("behind = %+v", behind)
	}
	states := map[string]outcome{}
	for _, each := range outcomes {
		states[each.attr] = each
	}
	if states["a"].state != stateCurrent || states["c"].problem != "cargo failed" || states["d"].state != stateFailed {
		t.Fatalf("outcomes = %+v", outcomes)
	}
}

func TestMessageNamesEveryUpstreamCommit(t *testing.T) {
	one := update{attr: "nixlytile", from: Source{Rev: oldRev, Version: "2026.11.24"},
		next: Source{URL: "https://github.com/aCeTotal/nixlytile", Branch: "main", Rev: newRev, Version: "2026.11.25"},
		log:  []string{"2222222 Fix resume"}}
	text := message([]update{one})
	if !strings.HasPrefix(text, "nixlytile: 2026.11.24 → 2026.11.25\n\n") || !strings.Contains(text, "  2222222 Fix resume\n") {
		t.Fatalf("message:\n%s", text)
	}
	two := one
	two.attr = "nixlymedia"
	if text := message([]update{one, two}); !strings.HasPrefix(text, "pkgs: update nixlymedia, nixlytile\n") {
		t.Fatalf("message:\n%s", text)
	}
}
