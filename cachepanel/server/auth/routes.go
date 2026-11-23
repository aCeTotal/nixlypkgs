package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"cachepanel/client"
	"cachepanel/rest"
)

var (
	errInvalidCredentials = &rest.Error{Status: http.StatusUnauthorized, Code: "invalid_credentials", Message: "Wrong username or password"}
	errTooManyAttempts    = &rest.Error{Status: http.StatusTooManyRequests, Code: "too_many_attempts", Message: "Too many attempts. Wait a minute."}
	errWrongPassword      = rest.Unprocessable("wrong_password", "The current password is wrong")
)

type me struct {
	User User   `json:"user"`
	CSRF string `json:"csrf"`
}

// Routes check credentials themselves.
func (s *Service) Routes() http.Handler {
	r := chi.NewRouter()
	r.Post("/login", rest.Handle(s.login))
	r.Post("/logout", rest.Handle(s.logout))
	r.Get("/me", rest.Handle(s.me))
	r.With(s.Authenticate).Post("/password", rest.Handle(s.changePassword))
	return r
}

func (s *Service) login(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	username := strings.ToLower(strings.TrimSpace(req.Username))
	if !s.byClient.Allow(client.Address(r).String()) || !s.byUser.Allow(username) {
		return errTooManyAttempts
	}
	var user User
	var hash string
	err := s.db.QueryRow(r.Context(), `SELECT id, username, password_hash FROM users WHERE username = $1`, username).
		Scan(&user.ID, &user.Username, &hash)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if user.ID == 0 {
		hash = decoyHash
	}
	matches, err := s.verify(r.Context(), hash, req.Password)
	if err != nil {
		return err
	}
	if !matches || user.ID == 0 {
		return errInvalidCredentials
	}
	token, csrf, err := s.sessions.create(r.Context(), user.ID)
	if err != nil {
		return err
	}
	setCookie(w, token, int(sessionTTL.Seconds()))
	return rest.WriteJSON(w, http.StatusOK, me{User: user, CSRF: csrf})
}

// verify bounds concurrent argon2 work.
func (s *Service) verify(ctx context.Context, hash, password string) (bool, error) {
	select {
	case s.hashing <- struct{}{}:
	case <-ctx.Done():
		return false, ctx.Err()
	}
	defer func() { <-s.hashing }()
	return verifyPassword(hash, password), nil
}

func (s *Service) logout(w http.ResponseWriter, r *http.Request) error {
	cookie, err := r.Cookie(sessionCookie)
	if err == nil {
		if err := s.sessions.delete(r.Context(), cookie.Value); err != nil {
			return err
		}
	}
	setCookie(w, "", -1)
	return rest.NoContent(w)
}

func (s *Service) me(w http.ResponseWriter, r *http.Request) error {
	current, err := s.authenticate(r)
	if err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, me(current))
}

func (s *Service) changePassword(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Current string `json:"current"`
		Next    string `json:"next"`
	}
	if err := rest.Decode(r, &req); err != nil {
		return err
	}
	if err := validatePassword(req.Next); err != nil {
		return err
	}
	user := From(r.Context())
	var hash string
	if err := s.db.QueryRow(r.Context(), `SELECT password_hash FROM users WHERE id = $1`, user.ID).Scan(&hash); err != nil {
		return err
	}
	matches, err := s.verify(r.Context(), hash, req.Current)
	if err != nil {
		return err
	}
	if !matches {
		return errWrongPassword
	}
	if _, err := s.db.Exec(r.Context(), `UPDATE users SET password_hash = $2, password_changed_at = now() WHERE id = $1`,
		user.ID, HashPassword(req.Next)); err != nil {
		return err
	}
	cookie, _ := r.Cookie(sessionCookie)
	if err := s.sessions.revokeOthers(r.Context(), user.ID, cookie.Value); err != nil {
		return err
	}
	return rest.NoContent(w)
}

func setCookie(w http.ResponseWriter, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    value,
		Path:     "/",
		MaxAge:   maxAge,
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
	})
}
