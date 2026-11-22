package wizard

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/go-chi/chi/v5"

	"cachepanel/analyse"
)

var (
	hashPattern   = regexp.MustCompile(`^[0-9a-f]{64}$`)
	uploadPattern = regexp.MustCompile(`^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$`)
	errNoUpload   = errors.New("fant ikke den opplastede filen")
	errFileName   = errors.New("filnavnet kan bare ha bokstaver, tall og . _ + -")
)

// Uploads keeps uploaded sources by content hash.
type Uploads struct {
	dir       string
	publicURL string
}

func NewUploads(dir, publicURL string) *Uploads {
	return &Uploads{dir: dir, publicURL: strings.TrimRight(publicURL, "/")}
}

// Save stores a stream and returns its sha256.
func (u *Uploads) Save(name string, body io.Reader) (string, error) {
	if !uploadPattern.MatchString(name) {
		return "", errFileName
	}
	if err := os.MkdirAll(u.dir, 0o750); err != nil {
		return "", err
	}
	root, err := os.OpenRoot(u.dir)
	if err != nil {
		return "", err
	}
	defer func() { _ = root.Close() }()
	partial := ".upload-" + rand.Text()
	tmp, err := root.Create(partial)
	if err != nil {
		return "", err
	}
	defer func() { _ = root.Remove(partial) }()
	digest := sha256.New()
	_, err = io.Copy(io.MultiWriter(tmp, digest), body)
	if err = errors.Join(err, tmp.Close()); err != nil {
		return "", err
	}
	hash := hex.EncodeToString(digest.Sum(nil))
	if err := root.Mkdir(hash, 0o750); err != nil && !errors.Is(err, fs.ErrExist) {
		return "", err
	}
	return hash, root.Rename(partial, hash+"/"+name)
}

func (u *Uploads) file(hash string) (string, error) {
	if !hashPattern.MatchString(hash) {
		return "", errNoUpload
	}
	entries, err := os.ReadDir(filepath.Join(u.dir, hash))
	if err != nil || len(entries) != 1 {
		return "", errNoUpload
	}
	return filepath.Join(u.dir, hash, entries[0].Name()), nil
}

// URL is where machines fetch an upload.
func (u *Uploads) URL(hash string) (string, error) {
	file, err := u.file(hash)
	if err != nil {
		return "", err
	}
	return u.publicURL + "/api/v1/sources/" + hash + "/" + url.PathEscape(filepath.Base(file)), nil
}

// Seed adds an upload like fetchurl.
func (u *Uploads) Seed(ctx context.Context, hash string) (analyse.Fetched, error) {
	file, err := u.file(hash)
	if err != nil {
		return analyse.Fetched{}, err
	}
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "nix-store", "--add-fixed", "sha256", file)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return analyse.Fetched{}, fmt.Errorf("legg i store: %w: %s", err, stderr.String())
	}
	raw, err := hex.DecodeString(hash)
	if err != nil {
		return analyse.Fetched{}, err
	}
	return analyse.Fetched{Path: strings.TrimSpace(string(out)), Hash: "sha256-" + base64.StdEncoding.EncodeToString(raw)}, nil
}

// Serve hands uploads out unauthenticated.
func (u *Uploads) Serve(w http.ResponseWriter, r *http.Request) {
	file, err := u.file(chi.URLParam(r, "hash"))
	if err != nil || filepath.Base(file) != chi.URLParam(r, "name") {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeFile(w, r, file)
}
