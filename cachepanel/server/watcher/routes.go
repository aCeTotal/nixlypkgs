package watcher

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"cachepanel/rest"
)

func (w *Watcher) Mount(r chi.Router) {
	r.Post("/watcher/pause", rest.Handle(w.pause))
	r.Post("/watcher/resume", rest.Handle(w.resume))
	r.Post("/watcher/poll", rest.Handle(w.poll))
	r.Post("/watcher/backfill", rest.Handle(w.restartBackfill))
}

func (w *Watcher) pause(rw http.ResponseWriter, r *http.Request) error {
	if _, err := w.db.Exec(r.Context(), `UPDATE watcher SET paused = true`); err != nil {
		return err
	}
	w.Poke()
	return rest.NoContent(rw)
}

func (w *Watcher) resume(rw http.ResponseWriter, r *http.Request) error {
	if _, err := w.db.Exec(r.Context(), `UPDATE watcher SET paused = false`); err != nil {
		return err
	}
	w.Poke()
	return rest.NoContent(rw)
}

func (w *Watcher) poll(rw http.ResponseWriter, _ *http.Request) error {
	w.Poke()
	return rest.NoContent(rw)
}

// restartBackfill walks further back in history.
func (w *Watcher) restartBackfill(rw http.ResponseWriter, r *http.Request) error {
	if _, err := w.db.Exec(r.Context(), `UPDATE watcher SET backfill_steps = 0, backfill_done = false`); err != nil {
		return err
	}
	w.Poke()
	return rest.NoContent(rw)
}
