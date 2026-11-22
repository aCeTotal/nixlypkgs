package wizard

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"cachepanel/rest"
)

const (
	logChunk    = 256 << 10
	uploadLimit = 4 << 30
)

var (
	errNoFile     = rest.BadRequest("no_file", "Forespørselen mangler en fil")
	errFileEdited = rest.Unprocessable("invalid_file", "Ugyldig filnavn")
)

func describe(files map[string][]byte) []file {
	described := []file{{Name: "default.nix", Text: string(files["default.nix"]), Size: len(files["default.nix"])}}
	for name, content := range files {
		if name == "default.nix" {
			continue
		}
		entry := file{Name: name, Size: len(content)}
		if utf8.Valid(content) {
			entry.Text = string(content)
		}
		described = append(described, entry)
	}
	return described
}

// saveTexts replaces edited text files.
func saveTexts(ctx context.Context, tx pgx.Tx, id int64, texts map[string]string) error {
	for name, text := range texts {
		if !uploadPattern.MatchString(name) || name == "default.nix" {
			return errFileEdited
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO recipe_files (recipe_id, name, content) VALUES ($1, $2, $3)
			ON CONFLICT (recipe_id, name) DO UPDATE SET content = EXCLUDED.content`, id, name, []byte(text)); err != nil {
			return err
		}
	}
	return nil
}

// log pages onward from ?from=.
func (s *Service) log(w http.ResponseWriter, r *http.Request) error {
	id, err := rest.ID(r, "id")
	if err != nil {
		return err
	}
	from, _ := strconv.ParseInt(r.URL.Query().Get("from"), 10, 64)
	f, err := os.Open(s.logPath(id))
	if os.IsNotExist(err) {
		return rest.WriteJSON(w, http.StatusOK, map[string]any{"text": "", "next": 0})
	}
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	chunk := make([]byte, logChunk)
	n, err := f.ReadAt(chunk, max(from, 0))
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]any{"text": strings.ToValidUTF8(string(chunk[:n]), "�"), "next": max(from, 0) + int64(n)})
}

func (s *Service) upload(w http.ResponseWriter, r *http.Request) error {
	r.Body = http.MaxBytesReader(w, r.Body, uploadLimit)
	parts, err := r.MultipartReader()
	if err != nil {
		return errNoFile
	}
	part, err := parts.NextPart()
	if err != nil || part.FormName() != "file" {
		return errNoFile
	}
	hash, err := s.lab.Uploads.Save(part.FileName(), part)
	if errors.Is(err, errFileName) {
		return rest.Unprocessable("invalid_file", err.Error())
	}
	if err != nil {
		return err
	}
	url, err := s.lab.Uploads.URL(hash)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusCreated, map[string]string{"hash": hash, "name": part.FileName(), "url": url})
}
