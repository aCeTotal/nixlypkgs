package editor

import (
	"github.com/go-chi/chi/v5"

	"cachepanel/rest"
)

// MountIndex bypasses the compressor.
func (x *Index) MountIndex(r chi.Router) {
	r.Get("/api/editor/nix", rest.Handle(x.serve))
}

func Mount(r chi.Router) {
	r.Post("/editor/format", rest.Handle(formatRoute))
}
