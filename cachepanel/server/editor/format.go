package editor

import (
	"context"
	"errors"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"cachepanel/rest"
)

const formatTimeout = 20 * time.Second

// format runs nixfmt, reporting parse errors.
func format(ctx context.Context, source string) (string, string, error) {
	ctx, cancel := context.WithTimeout(ctx, formatTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nixfmt", "-")
	cmd.Stdin = strings.NewReader(source)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if _, failed := errors.AsType[*exec.ExitError](err); failed {
		return "", reason(stderr.String()), nil
	}
	return string(out), "", err
}

// reason drops nixfmt's code frame.
func reason(stderr string) string {
	lines := strings.Split(strings.TrimSpace(stderr), "\n")
	for i, line := range lines {
		if strings.Contains(line, "^") {
			return strings.Join(lines[i+1:], ", ")
		}
	}
	return strings.Join(lines, ", ")
}

type formatted struct {
	Source string `json:"source"`
	Error  string `json:"error"`
}

func formatRoute(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Source string `json:"source"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	source, problem, err := format(r.Context(), req.Source)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, formatted{Source: source, Error: problem})
}
