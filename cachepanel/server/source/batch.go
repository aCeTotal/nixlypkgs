package source

import (
	"bufio"
	"context"
	"strconv"
	"strings"
	"time"
)

// FilesAt reads many files at one commit in one git run.
func (r *Repo) FilesAt(ctx context.Context, rev string, paths []string) (map[string]string, error) {
	var specs strings.Builder
	for _, path := range paths {
		specs.WriteString(rev + ":" + path + "\n")
	}
	out, err := r.run(ctx, call{args: []string{"cat-file", "--batch"}, stdin: strings.NewReader(specs.String())})
	if err != nil {
		return nil, err
	}
	files := make(map[string]string, len(paths))
	for _, path := range paths {
		header, rest, _ := strings.Cut(out, "\n")
		fields := strings.Fields(header)
		// Missing paths answer "<spec> missing" and nothing else.
		if len(fields) != 3 {
			out = rest
			continue
		}
		size, _ := strconv.Atoi(fields[2])
		size = min(size, len(rest))
		files[path] = rest[:size]
		out = strings.TrimPrefix(rest[size:], "\n")
	}
	return files, nil
}

// LastChanged finds when each path last changed on main.
func (r *Repo) LastChanged(ctx context.Context, paths []string) (map[string]time.Time, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	cmd := r.command(ctx, append([]string{"log", "--format=%x00%ct", "--name-only", r.ref(), "--"}, paths...)...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	changed := make(map[string]time.Time, len(paths))
	var when time.Time
	lines := bufio.NewScanner(stdout)
	for len(changed) < len(paths) && lines.Scan() {
		line := lines.Text()
		if seconds, found := strings.CutPrefix(line, "\x00"); found {
			unix, _ := strconv.ParseInt(seconds, 10, 64)
			when = time.Unix(unix, 0).UTC()
			continue
		}
		if _, seen := changed[line]; line != "" && !seen {
			changed[line] = when
		}
	}
	// Stopping early ends git; its exit status says nothing.
	cancel()
	_ = cmd.Wait()
	return changed, lines.Err()
}
