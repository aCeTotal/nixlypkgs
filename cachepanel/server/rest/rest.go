package rest

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const maxBodyBytes = 2 << 20

const (
	pgUniqueViolation     = "23505"
	pgForeignKeyViolation = "23503"
	pgCheckViolation      = "23514"
)

// Error is a client-facing failure.
type Error struct {
	Status  int
	Code    string
	Message string
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

func BadRequest(code, message string) *Error {
	return &Error{Status: http.StatusBadRequest, Code: code, Message: message}
}

func NotFound() *Error {
	return &Error{Status: http.StatusNotFound, Code: "not_found", Message: "Fant ikke ressursen"}
}

func Conflict(code, message string) *Error {
	return &Error{Status: http.StatusConflict, Code: code, Message: message}
}

func Unprocessable(code, message string) *Error {
	return &Error{Status: http.StatusUnprocessableEntity, Code: code, Message: message}
}

var (
	errInvalidBody = BadRequest("invalid_body", "Ugyldig forespørsel")
	errInternal    = &Error{Status: http.StatusInternalServerError, Code: "internal", Message: "Noe gikk galt. Prøv igjen."}
)

// Handle adapts an error-returning endpoint.
func Handle(endpoint func(http.ResponseWriter, *http.Request) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := endpoint(w, r); err != nil {
			WriteError(w, r, err)
		}
	}
}

func WriteJSON(w http.ResponseWriter, status int, body any) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(body)
}

// WriteRaw sends database-encoded JSON.
func WriteRaw(w http.ResponseWriter, body []byte) error {
	w.Header().Set("Content-Type", "application/json")
	_, err := w.Write(body)
	return err
}

func NoContent(w http.ResponseWriter) error {
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func WriteError(w http.ResponseWriter, r *http.Request, err error) {
	apiErr := classify(err)
	if apiErr.Status >= http.StatusInternalServerError {
		slog.ErrorContext(r.Context(), "request failed", "method", r.Method, "path", r.URL.Path, "error", err)
	}
	_ = WriteJSON(w, apiErr.Status, map[string]any{"error": map[string]string{"code": apiErr.Code, "message": apiErr.Message}})
}

func classify(err error) *Error {
	if apiErr, ok := errors.AsType[*Error](err); ok {
		return apiErr
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return NotFound()
	}
	pgErr, ok := errors.AsType[*pgconn.PgError](err)
	if !ok {
		return errInternal
	}
	switch pgErr.Code {
	case pgUniqueViolation:
		return Conflict("already_exists", "Finnes allerede")
	case pgForeignKeyViolation:
		return Conflict("in_use", "Er i bruk og kan ikke endres slik")
	case pgCheckViolation:
		return Unprocessable("invalid_value", "Ugyldig verdi")
	}
	return errInternal
}

// Decode reads strict JSON bodies.
func Decode(r *http.Request, target any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return errInvalidBody
	}
	return nil
}

// ID parses a numeric path parameter.
func ID(r *http.Request, name string) (int64, error) {
	id, err := strconv.ParseInt(chi.URLParam(r, name), 10, 64)
	if err != nil || id <= 0 {
		return 0, NotFound()
	}
	return id, nil
}
