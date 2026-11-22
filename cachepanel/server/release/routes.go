package release

import (
	"net/http"
	"regexp"

	"github.com/go-chi/chi/v5"

	"cachepanel/rest"
)

var treePattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

// Mount serves the machine API.
func (r *Releases) Mount(router chi.Router) {
	router.Get("/profiles", r.list)
	router.Get("/profiles/{name}", r.pointer)
	router.Get("/trees/{hash}.tar.gz", rest.Handle(r.tree))
}

func (r *Releases) list(w http.ResponseWriter, req *http.Request) {
	serve(w, req, r.current.Load().list)
}

func (r *Releases) pointer(w http.ResponseWriter, req *http.Request) {
	entry, found := r.Pointer(chi.URLParam(req, "name"))
	if !found {
		rest.WriteError(w, req, rest.NotFound())
		return
	}
	serve(w, req, entry)
}

// serve answers revalidations without a body.
func serve(w http.ResponseWriter, req *http.Request, entry Entry) {
	header := w.Header()
	header.Set("ETag", entry.ETag)
	header.Set("Cache-Control", "no-cache")
	if req.Header.Get("If-None-Match") == entry.ETag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	header.Set("Content-Type", "application/json")
	_, _ = w.Write(entry.Body)
}

// tree serves immutable, content-addressed archives.
func (r *Releases) tree(w http.ResponseWriter, req *http.Request) error {
	hash := chi.URLParam(req, "hash")
	if !treePattern.MatchString(hash) {
		return rest.NotFound()
	}
	tag := `"` + hash + `"`
	if req.Header.Get("If-None-Match") == tag {
		immutable(w, tag)
		w.WriteHeader(http.StatusNotModified)
		return nil
	}
	archive, found := r.current.Load().archives[hash]
	if !found {
		if err := r.db.QueryRow(req.Context(), `SELECT archive FROM trees WHERE hash = $1`, hash).Scan(&archive); err != nil {
			return err
		}
	}
	immutable(w, tag)
	w.Header().Set("Content-Type", "application/gzip")
	_, err := w.Write(archive)
	return err
}

func immutable(w http.ResponseWriter, tag string) {
	w.Header().Set("ETag", tag)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
}
