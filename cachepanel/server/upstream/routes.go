package upstream

import (
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/rest"
)

func (t *Tracker) Mount(r chi.Router) {
	r.Get("/upstream", rest.Handle(t.list))
	r.Post("/upstream/check", rest.Handle(t.check))
}

// Tracked is a pin and its status.
type Tracked struct {
	Attr        string     `json:"attr"`
	URL         string     `json:"url"`
	Follows     string     `json:"follows"`
	Rev         string     `json:"rev"`
	Version     string     `json:"version"`
	LatestRev   *string    `json:"latestRev"`
	State       string     `json:"state"`
	Error       *string    `json:"error"`
	CheckedAt   *time.Time `json:"checkedAt"`
	CommittedAt *time.Time `json:"committedAt"`
}

func (t *Tracker) list(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	head, err := t.repo.Head(ctx)
	if err != nil {
		return err
	}
	sources, problems, err := Sources(ctx, t.repo, head)
	if err != nil {
		return err
	}
	tracked := make([]Tracked, 0, len(sources)+len(problems))
	for attr, each := range sources {
		tracked = append(tracked, Tracked{Attr: attr, URL: each.URL, Follows: each.Follows(), Rev: each.Rev, Version: each.Version,
			State: string(stateCurrent)})
	}
	for attr, problem := range problems {
		message := problem.Error()
		tracked = append(tracked, Tracked{Attr: attr, State: string(stateFailed), Error: &message})
	}
	slices.SortFunc(tracked, func(a, b Tracked) int { return strings.Compare(a.Attr, b.Attr) })
	rows, err := t.db.Query(ctx, `SELECT attr, latest_rev, state::text, error, checked_at, committed_at FROM upstreams`)
	if err != nil {
		return err
	}
	var attr string
	var last Tracked
	_, err = pgx.ForEachRow(rows, []any{&attr, &last.LatestRev, &last.State, &last.Error, &last.CheckedAt, &last.CommittedAt}, func() error {
		index, found := slices.BinarySearchFunc(tracked, attr, func(each Tracked, attr string) int { return strings.Compare(each.Attr, attr) })
		if found && tracked[index].URL != "" {
			tracked[index].LatestRev, tracked[index].State, tracked[index].Error = last.LatestRev, last.State, last.Error
			tracked[index].CheckedAt, tracked[index].CommittedAt = last.CheckedAt, last.CommittedAt
		}
		return nil
	})
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, tracked)
}

// check retries failures right away.
func (t *Tracker) check(w http.ResponseWriter, r *http.Request) error {
	if err := t.retry(r.Context()); err != nil {
		return err
	}
	select {
	case t.wake <- struct{}{}:
	default:
	}
	return rest.NoContent(w)
}
