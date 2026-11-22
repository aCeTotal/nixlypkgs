package watcher

import (
	"time"

	"cachepanel/realtime"
	"cachepanel/repo"
)

// Phase is the watcher's activity.
type Phase string

const (
	Idle        Phase = "idle"
	Fetching    Phase = "fetching"
	Evaluating  Phase = "evaluating"
	Backfilling Phase = "backfilling"
	Paused      Phase = "paused"
)

type CommitInfo struct {
	SHA     string    `json:"sha"`
	Subject string    `json:"subject"`
	Time    time.Time `json:"time"`
}

// Status is what panels show.
type Status struct {
	Phase         Phase       `json:"phase"`
	Commit        *CommitInfo `json:"commit"`
	Head          string      `json:"head"`
	Started       *time.Time  `json:"started"`
	LastPoll      *time.Time  `json:"lastPoll"`
	LastError     string      `json:"lastError"`
	BackfillSteps int         `json:"backfillSteps"`
	BackfillLimit int         `json:"backfillLimit"`
	BackfillDone  bool        `json:"backfillDone"`
}

func (w *Watcher) Status() Status {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.status
}

func (w *Watcher) update(change func(*Status)) {
	w.mu.Lock()
	change(&w.status)
	current := w.status
	w.mu.Unlock()
	w.hub.Publish(realtime.WatcherChanged, current)
}

func (w *Watcher) working(phase Phase, c *repo.Commit) {
	now := time.Now()
	w.update(func(s *Status) {
		s.Phase, s.Started, s.Commit = phase, &now, nil
		if c != nil {
			s.Commit = &CommitInfo{SHA: c.SHA, Subject: c.Subject, Time: c.Time}
		}
	})
}
