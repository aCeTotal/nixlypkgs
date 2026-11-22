package modules

import (
	"context"
	"errors"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	"cachepanel/logtail"
	"cachepanel/rest"
)

const (
	parseTimeout = 20 * time.Second
	parseKeep    = 4 << 10
)

var (
	ansi     = regexp.MustCompile(`\x1b\[[0-9;]*[A-Za-z]`)
	position = regexp.MustCompile(`«stdin»:(\d+):(\d+)`)
)

// problem is a syntax error; empty when valid.
type problem struct {
	Error  string `json:"error"`
	Line   int    `json:"line,omitempty"`
	Column int    `json:"column,omitempty"`
}

// parse returns Nix's syntax error.
func parse(ctx context.Context, source string) (problem, error) {
	ctx, cancel := context.WithTimeout(ctx, parseTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nix-instantiate", "--parse", "-")
	cmd.Stdin = strings.NewReader(source)
	output := logtail.New(parseKeep)
	cmd.Stderr = output
	err := cmd.Run()
	if err == nil {
		return problem{}, nil
	}
	if _, rejected := errors.AsType[*exec.ExitError](err); !rejected {
		return problem{}, err
	}
	found := problem{Error: ansi.ReplaceAllString(output.String(), "")}
	if match := position.FindStringSubmatch(found.Error); match != nil {
		found.Line, _ = strconv.Atoi(match[1])
		found.Column, _ = strconv.Atoi(match[2])
	}
	return found, nil
}

func validSyntax(ctx context.Context, source string) error {
	found, err := parse(ctx, source)
	if err != nil {
		return err
	}
	if found.Error != "" {
		return rest.Unprocessable("invalid_nix", found.Error)
	}
	return nil
}
