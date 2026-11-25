package cache

import (
	"net/http"
	"regexp"

	"github.com/go-chi/chi/v5"
)

var (
	hashPattern = regexp.MustCompile(`^[0-9a-df-np-sv-z]{32}$`)
	narPattern  = regexp.MustCompile(`^[0-9a-z]+\.nar(\.[a-z0-9]+)?$`)
)

// Mount serves files by request path.
func (c *Cache) Mount(r chi.Router) {
	for _, route := range []struct {
		pattern string
		handler http.HandlerFunc
	}{
		{"/nix-cache-info", c.info},
		{"/{hash}.narinfo", c.narinfoFile},
		{"/nar/{name}", c.nar},
	} {
		r.Get(route.pattern, route.handler)
		r.Head(route.pattern, route.handler)
	}
}

func (c *Cache) info(w http.ResponseWriter, r *http.Request) {
	c.serve(w, r, "text/x-nix-cache-info")
}

func (c *Cache) narinfoFile(w http.ResponseWriter, r *http.Request) {
	if !hashPattern.MatchString(chi.URLParam(r, "hash")) {
		http.NotFound(w, r)
		return
	}
	c.serve(w, r, "text/x-nix-narinfo")
}

func (c *Cache) nar(w http.ResponseWriter, r *http.Request) {
	if !narPattern.MatchString(chi.URLParam(r, "name")) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	c.serve(w, r, "application/x-nix-nar")
}

func (c *Cache) serve(w http.ResponseWriter, r *http.Request, kind string) {
	w.Header().Set("Content-Type", kind)
	c.server.ServeHTTP(w, r)
}
