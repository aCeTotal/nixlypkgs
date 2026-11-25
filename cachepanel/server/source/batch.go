package source

import (
	"bufio"
	"context"
	"maps"
	"slices"
	"strconv"
	"strings"
	"time"
)

// FilesAt reads files in one run.
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
		// Missing paths print only "missing".
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

// LastChanged dates each path's change.
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
	// Early stop kills git harmlessly.
	cancel()
	_ = cmd.Wait()
	return changed, lines.Err()
}

// Paths lists every file on main.
func (r *Repo) Paths(ctx context.Context) ([]string, error) {
	head, err := r.Head(ctx)
	if err != nil {
		return nil, err
	}
	out, err := r.read(ctx, "ls-tree", "-r", "-z", "--name-only", head)
	if err != nil {
		return nil, err
	}
	return strings.Split(strings.TrimSuffix(out, "\x00"), "\x00"), nil
}

// FolderAt reads dir's files at rev.
func (r *Repo) FolderAt(ctx context.Context, rev, dir string) (map[string]string, error) {
	out, err := r.read(ctx, "ls-tree", "-z", "--name-only", rev, dir+"/")
	if err != nil || out == "" {
		return map[string]string{}, err
	}
	return r.FilesAt(ctx, rev, strings.Split(strings.TrimSuffix(out, "\x00"), "\x00"))
}

// FilesNamed reads dir/<child>/name by child.
func (r *Repo) FilesNamed(ctx context.Context, rev, dir, name string) (map[string]string, error) {
	out, err := r.read(ctx, "ls-tree", "-r", "-z", "--name-only", rev, dir+"/")
	if err != nil {
		return nil, err
	}
	paths := map[string]string{}
	for path := range strings.SplitSeq(strings.TrimSuffix(out, "\x00"), "\x00") {
		child, file, nested := strings.Cut(strings.TrimPrefix(path, dir+"/"), "/")
		if nested && file == name {
			paths[path] = child
		}
	}
	files, err := r.FilesAt(ctx, rev, slices.Collect(maps.Keys(paths)))
	if err != nil {
		return nil, err
	}
	named := make(map[string]string, len(files))
	for path, text := range files {
		named[paths[path]] = text
	}
	return named, nil
}
