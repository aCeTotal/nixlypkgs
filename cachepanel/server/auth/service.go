package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"cachepanel/ratelimit"
	"cachepanel/rest"
)

const (
	csrfHeader        = "X-Cachepanel-CSRF"
	loginWindow       = time.Minute
	attemptsPerUser   = 5
	attemptsPerClient = 20
	concurrentHashes  = 2
	purgeInterval     = time.Hour
)

var (
	errUnauthenticated = &rest.Error{Status: http.StatusUnauthorized, Code: "unauthenticated", Message: "Du må logge inn"}
	errCSRF            = &rest.Error{Status: http.StatusForbidden, Code: "csrf", Message: "Ugyldig sikkerhetsnøkkel – last siden på nytt"}
)

type User struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

type Service struct {
	db       *pgxpool.Pool
	sessions sessions
	byUser   *ratelimit.Limiter
	byClient *ratelimit.Limiter
	hashing  chan struct{}
}

func NewService(db *pgxpool.Pool) *Service {
	return &Service{
		db:       db,
		sessions: sessions{db: db},
		byUser:   ratelimit.New(attemptsPerUser, loginWindow),
		byClient: ratelimit.New(attemptsPerClient, loginWindow),
		hashing:  make(chan struct{}, concurrentHashes),
	}
}

// Run prunes limiters and sessions.
func (s *Service) Run(ctx context.Context) {
	go s.byUser.Run(ctx)
	go s.byClient.Run(ctx)
	ticker := time.NewTicker(purgeInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := s.sessions.purge(ctx); err != nil {
				slog.Warn("purge sessions", "error", err)
			}
		}
	}
}

type contextKey struct{}

func From(ctx context.Context) User {
	user, _ := ctx.Value(contextKey{}).(User)
	return user
}

// Authenticate requires session and CSRF.
func (s *Service) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		current, err := s.authenticate(r)
		if err != nil {
			rest.WriteError(w, r, err)
			return
		}
		if !safeMethod(r.Method) && subtle.ConstantTimeCompare([]byte(r.Header.Get(csrfHeader)), []byte(current.CSRF)) != 1 {
			rest.WriteError(w, r, errCSRF)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), contextKey{}, current.User)))
	})
}

func (s *Service) authenticate(r *http.Request) (session, error) {
	cookie, err := r.Cookie(sessionCookie)
	if err != nil || cookie.Value == "" {
		return session{}, errUnauthenticated
	}
	current, err := s.sessions.lookup(r.Context(), cookie.Value)
	if errors.Is(err, pgx.ErrNoRows) {
		return session{}, errUnauthenticated
	}
	return current, err
}

func safeMethod(method string) bool {
	return method == http.MethodGet || method == http.MethodHead || method == http.MethodOptions
}
