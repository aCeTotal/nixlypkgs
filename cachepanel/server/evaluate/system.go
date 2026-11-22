package evaluate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"cachepanel/logtail"
	"cachepanel/nixexpr"
)

const (
	systemTimeout = 20 * time.Minute
	references    = "nixlyos/reference/profiles"
)

// ErrSkipped means the revision predates checks.
var ErrSkipped = errors.New("revision has no reference hardware")

// References lists test hardware profiles.
func References(ctx context.Context, flakeRef string) ([]string, error) {
	var profiles []string
	err := eval(ctx, fmt.Sprintf(`
let
  flake = builtins.getFlake %s;
  root = "${flake}/%s";
  entries = builtins.readDir root;
in
if builtins.pathExists root && builtins.functionArgs flake.lib.mkNixlySystem ? profileTree
then builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries)
else [ ]`, nixexpr.String(flakeRef), references), &profiles)
	if err == nil && len(profiles) == 0 {
		return nil, ErrSkipped
	}
	return profiles, err
}

// System evaluates one reference profile.
func System(ctx context.Context, flakeRef, hardware, treeDir string) (string, error) {
	var drvPath string
	err := eval(ctx, fmt.Sprintf(`
let
  flake = builtins.getFlake %s;
  system = flake.lib.mkNixlySystem {
    hostName = "nixly-check";
    username = "nixly";
    stateVersion = "25.05";
    hardwareDir = "${flake}/%s/%s";
    profileTree = /. + %s;
  };
in
system.config.system.build.toplevel.drvPath`,
		nixexpr.String(flakeRef), references, hardware, nixexpr.String(treeDir)), &drvPath)
	return drvPath, err
}

func eval(ctx context.Context, expr string, target any) error {
	ctx, cancel := context.WithTimeout(ctx, systemTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix", "eval", "--json", "--impure", "--expr", expr)
	stderr := logtail.New(stderrKeep)
	cmd.Stderr = stderr
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("%w\n%s", err, strings.TrimSpace(stderr.String()))
	}
	return json.Unmarshal(out, target)
}
