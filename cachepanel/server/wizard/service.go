package wizard

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"sync"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/realtime"
	"cachepanel/recipe"
)

// State tracks a recipe's lifecycle.
type State string

const (
	Importing State = "importing"
	Drafted   State = "draft"
	Building  State = "building"
	Ready     State = "ready"
	Failed    State = "failed"
	Published State = "published"
)

const parallelBuilds = 2

const uniqueViolation = "23505"

// report holds notes, steps and hints.
type report struct {
	Notes []string `json:"notes"`
	Steps []string `json:"steps"`
	Hints []string `json:"hints"`
}

// Service runs the wizard for the panel.
type Service struct {
	db        *pgxpool.Pool
	hub       *realtime.Hub
	lab       *Lab
	publisher *Publisher
	dir       string
	poke      func()
	life      context.Context

	mu      sync.Mutex
	running map[int64]context.CancelFunc
	slots   chan struct{}
}

func NewService(life context.Context, db *pgxpool.Pool, hub *realtime.Hub, lab *Lab, publisher *Publisher, dir string, poke func()) *Service {
	return &Service{
		db: db, hub: hub, lab: lab, publisher: publisher, dir: dir, poke: poke, life: life,
		running: map[int64]context.CancelFunc{}, slots: make(chan struct{}, parallelBuilds),
	}
}

// Recover fails jobs a restart cut short.
func (s *Service) Recover(ctx context.Context) error {
	if err := os.MkdirAll(filepath.Join(s.dir, "roots"), 0o750); err != nil {
		return err
	}
	_, err := s.db.Exec(ctx, `
		UPDATE recipes SET state = 'failed', error = 'Avbrutt av en omstart av panelet', updated_at = now()
		WHERE state IN ('importing', 'building')`)
	return err
}

func (s *Service) logPath(id int64) string {
	return filepath.Join(s.dir, strconv.FormatInt(id, 10)+".log")
}

func (s *Service) rootPath(id int64) string {
	return filepath.Join(s.dir, "roots", strconv.FormatInt(id, 10))
}

// start runs a job under the server's lifetime.
func (s *Service) start(id int64, job func(context.Context)) {
	ctx, cancel := context.WithCancel(s.life)
	s.mu.Lock()
	s.running[id] = cancel
	s.mu.Unlock()
	go func() {
		defer func() {
			s.mu.Lock()
			delete(s.running, id)
			s.mu.Unlock()
			cancel()
		}()
		job(ctx)
	}()
}

func (s *Service) stop(id int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if cancel, ok := s.running[id]; ok {
		cancel()
	}
}

func (s *Service) importJob(id int64, req Request) func(context.Context) {
	return func(ctx context.Context) {
		draft, err := s.lab.Import(ctx, req)
		if err == nil {
			err = s.saveDraft(ctx, id, draft)
		}
		if err != nil {
			s.fail(id, err)
		}
		s.changed(id)
	}
}

func (s *Service) buildJob(id int64) func(context.Context) {
	return func(ctx context.Context) {
		s.slots <- struct{}{}
		defer func() { <-s.slots }()
		err := s.runBuild(ctx, id)
		if err != nil {
			s.fail(id, err)
		}
		s.changed(id)
	}
}

func (s *Service) runBuild(ctx context.Context, id int64) error {
	draft, previous, err := s.loadDraft(ctx, id)
	if err != nil {
		return err
	}
	log, err := os.Create(s.logPath(id))
	if err != nil {
		return err
	}
	defer func() { _ = log.Close() }()
	outcome, buildErr := s.lab.Build(ctx, &draft, s.rootPath(id), log)
	r := report{Notes: previous.Notes, Steps: outcome.Steps, Hints: outcome.Hints}
	state, message := Ready, ""
	if buildErr != nil {
		state, message = Failed, buildErr.Error()
	}
	if errors.Is(buildErr, context.Canceled) {
		message = "Bygget ble stoppet"
	}
	_, err = s.db.Exec(context.WithoutCancel(ctx), `
		UPDATE recipes SET spec = $2, report = $3, state = $4, error = $5, output = nullif($6, ''), updated_at = now()
		WHERE id = $1`, id, draft.Spec, r, state, nullable(message), outcome.Output)
	return err
}

func (s *Service) saveDraft(ctx context.Context, id int64, draft Draft) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE recipes SET attr = $2, spec = $3, report = $4, state = 'draft', error = NULL, updated_at = now()
			WHERE id = $1`, id, draft.Spec.Attr, draft.Spec, report{Notes: draft.Notes}); err != nil {
			if pgErr, ok := errors.AsType[*pgconn.PgError](err); ok && pgErr.Code == uniqueViolation {
				return fmt.Errorf("det finnes allerede en oppskrift for %s; rediger den i stedet", draft.Spec.Attr)
			}
			return err
		}
		return storeFiles(ctx, tx, id, draft.Files)
	})
}

func storeFiles(ctx context.Context, tx pgx.Tx, id int64, files map[string][]byte) error {
	if _, err := tx.Exec(ctx, `DELETE FROM recipe_files WHERE recipe_id = $1`, id); err != nil {
		return err
	}
	for name, content := range files {
		if _, err := tx.Exec(ctx, `INSERT INTO recipe_files (recipe_id, name, content) VALUES ($1, $2, $3)`, id, name, content); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) loadDraft(ctx context.Context, id int64) (Draft, report, error) {
	var draft Draft
	var r report
	if err := s.db.QueryRow(ctx, `SELECT spec, report FROM recipes WHERE id = $1`, id).Scan(&draft.Spec, &r); err != nil {
		return Draft{}, report{}, err
	}
	rows, err := s.db.Query(ctx, `SELECT name, content FROM recipe_files WHERE recipe_id = $1`, id)
	if err != nil {
		return Draft{}, report{}, err
	}
	defer rows.Close()
	draft.Files = map[string][]byte{}
	for rows.Next() {
		var name string
		var content []byte
		if err := rows.Scan(&name, &content); err != nil {
			return Draft{}, report{}, err
		}
		draft.Files[name] = content
	}
	draft.Notes = r.Notes
	return draft, r, rows.Err()
}

// files renders what a publish commits.
func (s *Service) files(ctx context.Context, draft Draft) (map[string][]byte, error) {
	source, err := recipe.Render(draft.Spec)
	if err == nil {
		source, err = recipe.Format(ctx, source)
	}
	if err != nil {
		return nil, err
	}
	files := map[string][]byte{"default.nix": []byte(source)}
	for name, content := range draft.Files {
		files[name] = content
	}
	return files, nil
}

func (s *Service) fail(id int64, cause error) {
	slog.Info("recipe failed", "recipe", id, "error", cause)
	_, err := s.db.Exec(s.life, `UPDATE recipes SET state = 'failed', error = $2, updated_at = now() WHERE id = $1`, id, cause.Error())
	if err != nil {
		slog.Error("record recipe failure", "recipe", id, "error", err)
	}
}

func (s *Service) changed(id int64) {
	s.hub.Publish(realtime.RecipeChanged, map[string]int64{"id": id})
}

func nullable(text string) *string {
	if text == "" {
		return nil
	}
	return &text
}

// origin describes an import, minus bodies.
func origin(req Request) []byte {
	names := make([]string, 0, len(req.Files))
	for name := range req.Files {
		names = append(names, name)
	}
	described, _ := json.Marshal(map[string]any{"origin": req.Origin, "name": req.Name, "url": req.URL, "ref": req.Ref, "upload": req.Upload, "files": names})
	return described
}
