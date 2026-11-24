package serve

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"

	"cachepanel/auth"
	"cachepanel/builds"
	"cachepanel/cache"
	"cachepanel/config"
	"cachepanel/database"
	"cachepanel/profiles"
	"cachepanel/realtime"
	"cachepanel/release"
	"cachepanel/repo"
	"cachepanel/signing"
	"cachepanel/source"
	"cachepanel/update"
	"cachepanel/watcher"
	"cachepanel/wizard"
)

var errNoCommit = errors.New("the panel has not evaluated any commit yet")

const (
	readHeaderTimeout = 10 * time.Second
	idleTimeout       = 2 * time.Minute
	shutdownTimeout   = 15 * time.Second
)

// Run serves until ctx ends.
func Run(ctx context.Context, cfg config.Config) error {
	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
	if err := database.Migrate(ctx, db); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	if err := auth.EnsureAdmin(ctx, db, cfg.AdminUser, cfg.AdminHash); err != nil {
		return err
	}
	origin, err := source.Open(ctx, cfg)
	if err != nil {
		return err
	}
	mirror, err := repo.Open(ctx, filepath.Join(cfg.StateDir, "nixlypkgs.git"), origin.Dir(), cfg.Branch)
	if err != nil {
		return err
	}
	hub := realtime.NewHub()
	releases := release.New(db, origin)
	store, err := cache.Open(cfg.CacheDir, cfg.CacheKey)
	if err != nil {
		return err
	}
	signer := signing.NewStore(db, filepath.Join(cfg.StateDir, "signing"), cfg.MicrosoftCerts)
	rebuilder := profiles.NewRebuilder(profiles.Deps{
		DB: db, Hub: hub, Mirror: mirror, Cache: store, Signer: signer, Source: origin,
		ChecksDir: filepath.Join(cfg.StateDir, "checks"), PublicURL: cfg.PublicURL, Published: releases.Trigger,
	})
	files := builds.NewFiles(cfg.StateDir)
	pool := builds.NewPool(db, hub, files, store, rebuilder.Trigger)
	follow := watcher.New(db, hub, mirror, pool, files, rebuilder.Trigger)
	lab := &wizard.Lab{Flake: headFlake(db, mirror), Uploads: wizard.NewUploads(filepath.Join(cfg.StateDir, "sources"), cfg.PublicURL)}
	publisher := &wizard.Publisher{Mirror: mirror, Remote: origin.Dir(), Branch: cfg.Branch}
	recipes := wizard.NewService(ctx, db, hub, lab, publisher, filepath.Join(cfg.StateDir, "recipes"), follow.Poke)
	if err := recipes.Recover(ctx); err != nil {
		return err
	}
	clones, err := origin.Handler()
	if err != nil {
		return err
	}
	panel := &app{
		cfg: cfg, db: db, hub: hub, auth: auth.NewService(db), mirror: mirror, releases: releases, rebuilder: rebuilder,
		pool: pool, watcher: follow, recipes: recipes, uploads: lab.Uploads, cache: store,
		trust:  &signing.Routes{Store: signer, Hub: hub},
		source: &source.Routes{Repo: origin, Keys: source.Keys{DB: db}, Hub: hub, Poke: follow.Poke, Remote: cfg.SSHRemote},
		clones: clones,
		update: &update.Updater{DB: db, Hub: hub, Watcher: follow, Dir: cfg.UpdateDir},
	}

	group, ctx := errgroup.WithContext(ctx)
	group.Go(func() error { panel.auth.Run(ctx); return nil })
	group.Go(func() error { return releases.Run(ctx) })
	group.Go(func() error {
		return lead(ctx, db, func(ctx context.Context) error {
			workers, ctx := errgroup.WithContext(ctx)
			workers.Go(func() error { return pool.Run(ctx) })
			workers.Go(func() error { return follow.Run(ctx) })
			workers.Go(func() error { return rebuilder.Run(ctx) })
			workers.Go(func() error { return store.Run(ctx, liveRoots(pool, rebuilder)) })
			workers.Go(func() error { return panel.update.Run(ctx) })
			return workers.Wait()
		})
	})
	group.Go(func() error { return listen(ctx, cfg.HTTPAddr, panel.routes()) })
	return group.Wait()
}

func listen(ctx context.Context, addr string, handler http.Handler) error {
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: readHeaderTimeout,
		IdleTimeout:       idleTimeout,
		BaseContext:       func(net.Listener) context.Context { return ctx },
	}
	stop := context.AfterFunc(ctx, func() {
		shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), shutdownTimeout)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	})
	defer stop()
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("listen on %s: %w", addr, err)
	}
	return nil
}

// liveRoots is everything the cache serves.
func liveRoots(pool *builds.Pool, rebuilder *profiles.Rebuilder) cache.Roots {
	return func(ctx context.Context) ([]string, error) {
		versions, err := pool.Roots(ctx)
		if err != nil {
			return nil, err
		}
		systems, err := rebuilder.Released()
		return append(versions, systems...), err
	}
}

// headFlake picks the newest evaluated commit.
func headFlake(db *pgxpool.Pool, mirror *repo.Mirror) func(context.Context) (string, error) {
	return func(ctx context.Context) (string, error) {
		var sha string
		err := db.QueryRow(ctx, `SELECT sha FROM commits WHERE eval_state = 'done' ORDER BY position DESC LIMIT 1`).Scan(&sha)
		if errors.Is(err, pgx.ErrNoRows) {
			return "", errNoCommit
		}
		return mirror.FlakeRef(sha), err
	}
}
