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

// Mount serves the cache to nix clients.
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
	c.serve(w, r, "nix-cache-info", "text/x-nix-cache-info")
}

func (c *Cache) narinfoFile(w http.ResponseWriter, r *http.Request) {
	hash := chi.URLParam(r, "hash")
	if !hashPattern.MatchString(hash) {
		http.NotFound(w, r)
		return
	}
	c.serve(w, r, hash+narinfoSuffix, "text/x-nix-narinfo")
}

func (c *Cache) nar(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	if !narPattern.MatchString(name) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	c.serve(w, r, "nar/"+name, "application/x-nix-nar")
}

func (c *Cache) serve(w http.ResponseWriter, r *http.Request, name, kind string) {
	w.Header().Set("Content-Type", kind)
	http.ServeFileFS(w, r, c.files, name)
}
