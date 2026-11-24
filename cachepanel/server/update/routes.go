package update

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"cachepanel/realtime"
	"cachepanel/rest"
)

func (u *Updater) Mount(r chi.Router) {
	r.Get("/update", rest.Handle(u.overview))
	r.Put("/update", rest.Handle(u.toggle))
}

type overview struct {
	Configured bool    `json:"configured"`
	Enabled    bool    `json:"enabled"`
	Running    string  `json:"running"`
	Newest     *Target `json:"newest"`
	Idle       bool    `json:"idle"`
	Status     *Status `json:"status"`
}

func (u *Updater) overview(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	view := overview{Configured: u.Dir != ""}
	if err := u.DB.QueryRow(ctx, `SELECT enabled FROM panel_update`).Scan(&view.Enabled); err != nil {
		return err
	}
	self, err := running()
	if err != nil {
		return err
	}
	view.Running = self
	target, found, err := newest(ctx, u.DB)
	if err != nil {
		return err
	}
	if found {
		view.Newest = &target
	}
	idle, status := u.snapshot()
	view.Idle = idle
	if status.Phase != "" {
		view.Status = &status
	}
	return rest.WriteJSON(w, http.StatusOK, view)
}

type switchRequest struct {
	Enabled bool `json:"enabled"`
}

func (u *Updater) toggle(w http.ResponseWriter, r *http.Request) error {
	var req switchRequest
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if _, err := u.DB.Exec(r.Context(), `UPDATE panel_update SET enabled = $1`, req.Enabled); err != nil {
		return err
	}
	u.Hub.Publish(realtime.UpdateChanged, map[string]bool{"enabled": req.Enabled})
	return rest.NoContent(w)
}
