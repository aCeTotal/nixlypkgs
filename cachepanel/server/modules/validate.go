package modules

import (
	"context"
	"errors"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"cachepanel/logtail"
	"cachepanel/rest"
)

const (
	parseTimeout = 20 * time.Second
	parseKeep    = 4 << 10
)

var ansi = regexp.MustCompile(`\x1b\[[0-9;]*[A-Za-z]`)

// parse returns Nix's syntax error.
func parse(ctx context.Context, source string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, parseTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix-instantiate", "--parse", "-")
	cmd.Stdin = strings.NewReader(source)
	output := logtail.New(parseKeep)
	cmd.Stderr = output
	err := cmd.Run()
	if err == nil {
		return "", nil
	}
	if _, rejected := errors.AsType[*exec.ExitError](err); !rejected {
		return "", err
	}
	return ansi.ReplaceAllString(output.String(), ""), nil
}

func validSyntax(ctx context.Context, source string) error {
	problem, err := parse(ctx, source)
	if err != nil {
		return err
	}
	if problem != "" {
		return rest.Unprocessable("invalid_nix", problem)
	}
	return nil
}
