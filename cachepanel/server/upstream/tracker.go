package upstream

import (
	"context"
	"fmt"
	"log/slog"
	"maps"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"

	"cachepanel/realtime"
	"cachepanel/source"
)

const (
	pollInterval = time.Minute
	// Parallel fetches and hash builds.
	fetchers  = 8
	preparers = 4
	shortRev  = 12
)

// Tracker pins upstream commits on main.
type Tracker struct {
	db   *pgxpool.Pool
	hub  *realtime.Hub
	repo *source.Repo
	dir  string
	// poke starts evaluating a new commit.
	poke func()
	wake chan struct{}
}

func New(db *pgxpool.Pool, hub *realtime.Hub, repo *source.Repo, dir string, poke func()) *Tracker {
	return &Tracker{db: db, hub: hub, repo: repo, dir: dir, poke: poke, wake: make(chan struct{}, 1)}
}

func (t *Tracker) Run(ctx context.Context) error {
	for {
		if err := t.pass(ctx); err != nil && ctx.Err() == nil {
			slog.Error("upstream", "error", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-t.wake:
		case <-time.After(pollInterval):
		}
	}
}

// probe is one upstream tip.
type probe struct {
	attr   string
	latest Latest
	err    error
}

// update is one pending pin.
type update struct {
	attr string
	from Source
	next Source
	log  []string
	err  error
}

func (t *Tracker) pass(ctx context.Context) error {
	head, err := t.repo.Head(ctx)
	if err != nil {
		return err
	}
	sources, problems, err := Sources(ctx, t.repo, head)
	if err != nil {
		return err
	}
	if err := t.forget(ctx, append(slices.Collect(maps.Keys(sources)), slices.Collect(maps.Keys(problems))...)); err != nil {
		return err
	}
	seen, err := t.known(ctx)
	if err != nil {
		return err
	}
	outcomes, behind := classify(t.probe(ctx, sources), sources, seen)
	for attr, problem := range problems {
		outcomes = append(outcomes, failed(attr, "", problem))
	}
	if err := t.mark(ctx, behind); err != nil {
		return err
	}
	ready := t.prepare(ctx, head, behind)
	committed, err := t.commit(ctx, head, ready)
	return t.record(ctx, append(outcomes, settled(ready, committed, err)...))
}

// classify separates current from behind.
func classify(probes []probe, sources map[string]Source, known map[string]seen) ([]outcome, []update) {
	outcomes := []outcome{}
	behind := []update{}
	for _, each := range probes {
		was, pinned := known[each.attr], sources[each.attr]
		switch {
		case each.err != nil:
			outcomes = append(outcomes, failed(each.attr, "", each.err))
		case each.latest.Rev == pinned.Rev:
			outcomes = append(outcomes, outcome{attr: each.attr, latestRev: each.latest.Rev, state: stateCurrent})
		// Failed revisions wait for newer.
		case was.State == stateFailed && was.LatestRev == each.latest.Rev:
			outcomes = append(outcomes, outcome{attr: each.attr, latestRev: each.latest.Rev, state: stateFailed, problem: was.Error})
		default:
			next := pinned
			next.Rev, next.Version = each.latest.Rev, each.latest.Version
			behind = append(behind, update{attr: each.attr, from: pinned, next: next})
		}
	}
	return outcomes, behind
}

// settled records prepared pins.
func settled(ready []update, committed bool, refused error) []outcome {
	outcomes := make([]outcome, 0, len(ready))
	for _, each := range ready {
		switch {
		case each.err != nil:
			outcomes = append(outcomes, failed(each.attr, each.next.Rev, each.err))
		case refused != nil:
			outcomes = append(outcomes, failed(each.attr, "", refused))
		default:
			outcomes = append(outcomes, outcome{attr: each.attr, latestRev: each.next.Rev, state: stateCurrent, committed: committed})
		}
	}
	return outcomes
}

// probe fetches each upstream once.
func (t *Tracker) probe(ctx context.Context, sources map[string]Source) []probe {
	byURL := map[string][]string{}
	for attr, each := range sources {
		byURL[each.URL] = append(byURL[each.URL], attr)
	}
	var mu sync.Mutex
	probes := make([]probe, 0, len(sources))
	group, ctx := errgroup.WithContext(ctx)
	group.SetLimit(fetchers)
	for url, attrs := range byURL {
		group.Go(func() error {
			repo := cloneOf(t.dir, url)
			fetched := repo.fetch(ctx)
			for _, attr := range attrs {
				found := probe{attr: attr, err: fetched}
				if fetched == nil {
					found.latest, found.err = repo.latest(ctx, sources[attr])
				}
				mu.Lock()
				probes = append(probes, found)
				mu.Unlock()
			}
			return nil
		})
	}
	_ = group.Wait()
	return probes
}

// prepare hashes each newer revision.
func (t *Tracker) prepare(ctx context.Context, head string, behind []update) []update {
	group, ctx := errgroup.WithContext(ctx)
	group.SetLimit(preparers)
	for i := range behind {
		each := &behind[i]
		group.Go(func() error {
			each.err = t.pin(ctx, head, each)
			return nil
		})
	}
	_ = group.Wait()
	return behind
}

func (t *Tracker) pin(ctx context.Context, head string, each *update) error {
	hash, err := prefetch(ctx, each.next.URL, each.next.Rev)
	if err != nil {
		return err
	}
	each.next.Hash = hash
	if each.next, err = vendor(ctx, t.repo, head, each.attr, each.next); err != nil {
		return err
	}
	each.log, err = cloneOf(t.dir, each.next.URL).log(ctx, each.from.Rev, each.next.Rev)
	return err
}

// commit writes all pins at once.
func (t *Tracker) commit(ctx context.Context, head string, ready []update) (bool, error) {
	pinned := slices.DeleteFunc(slices.Clone(ready), func(each update) bool { return each.err != nil })
	if len(pinned) == 0 {
		return false, nil
	}
	changes := make([]source.FileChange, len(pinned))
	for i, each := range pinned {
		text, err := each.next.Encode()
		if err != nil {
			return false, err
		}
		changes[i] = source.FileChange{Path: sourcePath(each.attr), Content: &text}
	}
	sha, err := t.repo.Commit(ctx, source.Edit{Base: head, Message: message(pinned), Changes: changes}, t.repo.Robot())
	if err != nil {
		return false, err
	}
	t.poke()
	t.hub.Publish(realtime.SourceChanged, map[string]string{"sha": sha})
	return true, nil
}

// message lists derivations and commits.
func message(pinned []update) string {
	slices.SortFunc(pinned, func(a, b update) int { return strings.Compare(a.attr, b.attr) })
	var b strings.Builder
	b.WriteString(subject(pinned) + "\n")
	for _, each := range pinned {
		fmt.Fprintf(&b, "\n%s follows %s %s, %s..%s:\n", each.attr, each.next.URL, each.next.Follows(),
			each.from.Rev[:shortRev], each.next.Rev[:shortRev])
		for _, line := range each.log {
			b.WriteString("  " + line + "\n")
		}
	}
	return b.String()
}

func subject(pinned []update) string {
	if len(pinned) == 1 {
		return fmt.Sprintf("%s: %s → %s", pinned[0].attr, pinned[0].from.Version, pinned[0].next.Version)
	}
	names := make([]string, len(pinned))
	for i, each := range pinned {
		names[i] = each.attr
	}
	return "pkgs: update " + strings.Join(names, ", ")
}
