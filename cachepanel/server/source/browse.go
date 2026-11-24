package source

import (
	"cmp"
	"context"
	"io/fs"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"cachepanel/rest"
)

const maxFile = 1 << 20

var (
	errPath = rest.Unprocessable("invalid_path", "Use a path inside the repository, like pkgs/foo/default.nix")
	// ErrNoFile is a path missing at that commit.
	ErrNoFile = rest.NotFound()
)

// Entry is one name in a folder.
type Entry struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Dir  bool   `json:"dir"`
	Size int64  `json:"size"`
}

// Listing is a folder at main.
type Listing struct {
	Head    string  `json:"head"`
	Entries []Entry `json:"entries"`
}

// Blob is a file at main.
type Blob struct {
	Head   string `json:"head"`
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	Binary bool   `json:"binary"`
	Text   string `json:"text"`
}

// validPath refuses escapes and control characters.
func validPath(path string) bool {
	return fs.ValidPath(path) && path != "." && !strings.ContainsFunc(path, func(r rune) bool { return r < ' ' || r == 0x7f })
}

// Tree lists a folder, folders first.
func (r *Repo) Tree(ctx context.Context, dir string) (Listing, error) {
	if dir != "" && !validPath(dir) {
		return Listing{}, errPath
	}
	head, err := r.Head(ctx)
	if err != nil {
		return Listing{}, err
	}
	args := []string{"ls-tree", "-z", "-l", head}
	if dir != "" {
		args = append(args, "--", dir+"/")
	}
	out, err := r.read(ctx, args...)
	if err != nil {
		return Listing{}, err
	}
	entries := []Entry{}
	for record := range strings.SplitSeq(strings.TrimSuffix(out, "\x00"), "\x00") {
		if entry, ok := parseEntry(record); ok {
			entries = append(entries, entry)
		}
	}
	if dir != "" && len(entries) == 0 {
		return Listing{}, rest.NotFound()
	}
	slices.SortFunc(entries, func(a, b Entry) int {
		return cmp.Or(cmp.Compare(rank(a), rank(b)), strings.Compare(a.Name, b.Name))
	})
	return Listing{Head: head, Entries: entries}, nil
}

// parseEntry reads "mode type oid size\tpath".
func parseEntry(record string) (Entry, bool) {
	meta, path, found := strings.Cut(record, "\t")
	fields := strings.Fields(meta)
	if !found || len(fields) != 4 {
		return Entry{}, false
	}
	size, _ := strconv.ParseInt(fields[3], 10, 64)
	name := path[strings.LastIndexByte(path, '/')+1:]
	return Entry{Name: name, Path: path, Dir: fields[1] == "tree", Size: size}, true
}

// File reads one file at main.
func (r *Repo) File(ctx context.Context, path string) (Blob, error) {
	head, err := r.Head(ctx)
	if err != nil {
		return Blob{}, err
	}
	return r.FileAt(ctx, head, path)
}

// FileAt reads one file at a commit.
func (r *Repo) FileAt(ctx context.Context, rev, path string) (Blob, error) {
	if !validPath(path) {
		return Blob{}, errPath
	}
	if !shaPattern.MatchString(rev) {
		return Blob{}, ErrNoFile
	}
	out, err := r.run(ctx, call{args: []string{"cat-file", "--batch"}, stdin: strings.NewReader(rev + ":" + path + "\n")})
	if err != nil {
		return Blob{}, err
	}
	// "<oid> blob <size>", then the content.
	header, content, _ := strings.Cut(out, "\n")
	fields := strings.Fields(header)
	if len(fields) != 3 || fields[1] != "blob" {
		return Blob{}, ErrNoFile
	}
	blob := Blob{Head: rev, Path: path}
	blob.Size, _ = strconv.ParseInt(fields[2], 10, 64)
	content = content[:min(len(content), int(blob.Size))]
	blob.Binary = blob.Size > maxFile || !utf8.ValidString(content) || strings.IndexByte(content, 0) >= 0
	if !blob.Binary {
		blob.Text = content
	}
	return blob, nil
}

// rank puts folders first.
func rank(entry Entry) int {
	if entry.Dir {
		return 0
	}
	return 1
}
