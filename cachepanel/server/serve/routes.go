package serve

import (
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"path"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/auth"
	"cachepanel/builds"
	"cachepanel/cache"
	"cachepanel/client"
	"cachepanel/commits"
	"cachepanel/config"
	"cachepanel/editor"
	"cachepanel/modules"
	"cachepanel/overview"
	"cachepanel/packages"
	"cachepanel/profiles"
	"cachepanel/realtime"
	"cachepanel/release"
	"cachepanel/repo"
	"cachepanel/rest"
	"cachepanel/signing"
	"cachepanel/source"
	"cachepanel/update"
	"cachepanel/upstream"
	"cachepanel/watcher"
	"cachepanel/wizard"
)

const (
	compressionLevel = 5
	machineTimeout   = 30 * time.Second
)

const contentSecurityPolicy = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " +
	"font-src 'self'; connect-src 'self'; script-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"

type app struct {
	cfg       config.Config
	db        *pgxpool.Pool
	hub       *realtime.Hub
	auth      *auth.Service
	mirror    *repo.Mirror
	releases  *release.Releases
	rebuilder *profiles.Rebuilder
	pool      *builds.Pool
	watcher   *watcher.Watcher
	recipes   *wizard.Service
	uploads   *wizard.Uploads
	cache     *cache.Cache
	trust     *signing.Routes
	source    *source.Routes
	clones    http.Handler
	update    *update.Updater
	editor    *editor.Index
	tracker   *upstream.Tracker
}

func (a *app) routes() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer, securityHeaders)
	r.Get("/api/health", rest.Handle(a.health))
	r.Route("/api/v1", func(machine chi.Router) {
		machine.Use(middleware.Timeout(machineTimeout))
		a.releases.Mount(machine)
		a.trust.MountMachine(machine)
	})
	// Large downloads outlive the machine timeout.
	r.Get("/api/v1/sources/{hash}/{name}", a.uploads.Serve)
	r.With(a.auth.Authenticate).Get("/api/ws", a.hub.ServeWS)
	a.cache.Mount(r)
	r.Handle("/source.git/*", a.clones)
	a.editor.MountIndex(r.With(a.auth.Authenticate))

	compressed := r.With(middleware.Compress(compressionLevel))
	compressed.With(logWrites).Mount("/api/auth", a.auth.Routes())
	compressed.Route("/api", func(api chi.Router) {
		api.Use(a.auth.Authenticate, logWrites)
		api.NotFound(rest.Handle(func(http.ResponseWriter, *http.Request) error { return rest.NotFound() }))
		overview.New(a.db, a.watcher, a.pool, a.cfg.CacheDir).Mount(api)
		packages.New(a.db, a.hub, a.pool, a.rebuilder.Trigger).Mount(api)
		commits.New(a.db, a.watcher.Poke).Mount(api)
		(&modules.Modules{DB: a.db, Hub: a.hub, Repo: a.source.Repo, Poke: a.watcher.Poke, Used: a.rebuilder.ModuleUsed}).Mount(api)
		a.rebuilder.Mount(api)
		(&profiles.Routes{Rebuilder: a.rebuilder, Poke: a.watcher.Poke}).Mount(api)
		a.watcher.Mount(api)
		a.recipes.Mount(api)
		a.trust.Mount(api)
		a.source.Mount(api)
		a.update.Mount(api)
		a.tracker.Mount(api)
		editor.Mount(api)
	})
	if a.cfg.WebRoot != "" {
		compressed.Handle("/*", spa(a.cfg.WebRoot))
	}
	return r
}

func (a *app) health(w http.ResponseWriter, r *http.Request) error {
	if err := a.db.Ping(r.Context()); err != nil {
		return &rest.Error{Status: http.StatusServiceUnavailable, Code: "database_unavailable", Message: "The database is not responding"}
	}
	return rest.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// logWrites records state changes without bodies.
func logWrites(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead {
			next.ServeHTTP(w, r)
			return
		}
		recorder := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(recorder, r)
		slog.InfoContext(r.Context(), "request", "method", r.Method, "path", r.URL.Path, "status", recorder.Status(),
			"user", auth.From(r.Context()).Username, "client", client.Address(r).String())
	})
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", contentSecurityPolicy)
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Permissions-Policy", "camera=(), geolocation=(), microphone=()")
		if client.HTTPS(r) {
			h.Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
}

// spa falls back to index.html.
func spa(root string) http.Handler {
	files := os.DirFS(root)
	server := http.FileServerFS(files)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if _, err := fs.Stat(files, name); err != nil || name == "" {
			w.Header().Set("Cache-Control", "no-cache")
			http.ServeFileFS(w, r, files, "index.html")
			return
		}
		if strings.HasPrefix(name, "assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		}
		server.ServeHTTP(w, r)
	})
}
