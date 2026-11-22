package depmap

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"cachepanel/nixexpr"
)

const resolveTimeout = 5 * time.Minute

// Result is a need's chosen attrs.
type Result struct {
	Name    string   `json:"name"`
	Attrs   []string `json:"attrs"`
	Missing bool     `json:"missing"`
}

// Resolve picks the first existing alternative.
func Resolve(ctx context.Context, flakeRef string, needs []Need) ([]Result, error) {
	alternatives := make([][][]string, len(needs))
	for i, need := range needs {
		alternatives[i] = need.Alternatives
		if need.Dropped || need.Alternatives == nil {
			alternatives[i] = [][]string{}
		}
	}
	encoded, err := json.Marshal(alternatives)
	if err != nil {
		return nil, err
	}
	expr := `let
  pkgs = ` + nixexpr.Pkgs(flakeRef) + `;
  inherit (pkgs) lib;
  usable = value: !(lib.isDerivation value) || lib.meta.availableOn pkgs.stdenv.hostPlatform value;
  has = name: let path = lib.splitString "." name; found = builtins.tryEval (lib.getAttrFromPath path pkgs); in
    lib.hasAttrByPath path pkgs && found.success && usable found.value;
in map (lib.findFirst (lib.all has) null) (builtins.fromJSON ` + nixexpr.String(string(encoded)) + `)`
	ctx, cancel := context.WithTimeout(ctx, resolveTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--impure", "--json", "--expr", expr)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("resolve dependencies: %w\n%s", err, stderr.String())
	}
	var picked [][]string
	if err := json.Unmarshal(out, &picked); err != nil {
		return nil, err
	}
	results := make([]Result, len(needs))
	for i, need := range needs {
		results[i] = Result{Name: need.Name, Attrs: picked[i], Missing: picked[i] == nil && !need.Dropped}
	}
	return results, nil
}
