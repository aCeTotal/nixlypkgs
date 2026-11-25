package signing

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"encoding/pem"
	"errors"
	"net/http"
	"slices"
	"time"

	"github.com/go-chi/chi/v5"

	"cachepanel/realtime"
	"cachepanel/rest"
)

// Routes manage the NixlyOS CA.
type Routes struct {
	Store *Store
	Hub   *realtime.Hub
}

func (t *Routes) Mount(r chi.Router) {
	r.Get("/trust", rest.Handle(t.overview))
	r.Post("/trust/ca", rest.Handle(t.create))
	r.Get("/trust/ca/{id}.pem", rest.Handle(t.cert(false)))
	r.Get("/trust/ca/{id}.der", rest.Handle(t.cert(true)))
	r.Get("/trust/epic.zip", rest.Handle(t.submission))
}

// MountMachine serves machines and builds.
func (t *Routes) MountMachine(r chi.Router) {
	r.Get("/ca.pem", rest.Handle(t.active(false)))
	r.Get("/ca.der", rest.Handle(t.active(true)))
	r.Get("/signatures/{hash}.tar", t.bundle)
	r.Get("/secureboot/{from}/{variable}.auth", rest.Handle(t.update))
}

type overview struct {
	Active     *CA        `json:"active"`
	History    []CA       `json:"history"`
	Signatures int64      `json:"signatures"`
	Firmware   []Database `json:"firmware"`
	Releases   []Release  `json:"releases"`
	Rules      []Rule     `json:"rules"`
	Limits     []string   `json:"limits"`
}

func (t *Routes) overview(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	history, err := t.Store.List(ctx)
	if err != nil {
		return err
	}
	releases, err := t.Store.releases(ctx)
	if err != nil {
		return err
	}
	view := overview{History: history, Firmware: []Database{}, Releases: releases, Rules: rules, Limits: limits}
	for i := range history {
		if history[i].RetiredAt == nil {
			view.Active = &history[i]
		}
	}
	if view.Active == nil {
		return rest.WriteJSON(w, http.StatusOK, view)
	}
	if view.Firmware, err = t.Store.Firmware(ctx); err != nil {
		return err
	}
	if err := t.Store.db.QueryRow(ctx, `SELECT count(*) FROM signatures WHERE ca_id = $1`, view.Active.ID).Scan(&view.Signatures); err != nil {
		return err
	}
	return rest.WriteJSON(w, http.StatusOK, view)
}

// update serves firmware key updates.
func (t *Routes) update(w http.ResponseWriter, r *http.Request) error {
	variable := Variable(chi.URLParam(r, "variable"))
	if !slices.Contains(Variables, variable) {
		return rest.NotFound()
	}
	update, err := t.Store.Update(r.Context(), chi.URLParam(r, "from"), variable)
	if errors.Is(err, ErrNoCA) || errors.Is(err, ErrUnknownCA) {
		return rest.NotFound()
	}
	if err != nil {
		return err
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(update))
	return nil
}

func (t *Routes) create(w http.ResponseWriter, r *http.Request) error {
	ca, err := t.Store.Create(r.Context())
	if err != nil {
		return err
	}
	t.Hub.Publish(realtime.TrustChanged, map[string]int64{"id": ca.ID})
	return rest.WriteJSON(w, http.StatusCreated, ca)
}

func (t *Routes) cert(der bool) func(http.ResponseWriter, *http.Request) error {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := rest.ID(r, "id")
		if err != nil {
			return err
		}
		var certPEM string
		if err := t.Store.db.QueryRow(r.Context(), `SELECT cert_pem FROM signing_cas WHERE id = $1`, id).Scan(&certPEM); err != nil {
			return err
		}
		return writeCert(w, certPEM, der)
	}
}

func (t *Routes) active(der bool) func(http.ResponseWriter, *http.Request) error {
	return func(w http.ResponseWriter, r *http.Request) error {
		ca, err := t.Store.Active(r.Context())
		if errors.Is(err, ErrNoCA) {
			return rest.NotFound()
		}
		if err != nil {
			return err
		}
		return writeCert(w, ca.CertPEM, der)
	}
}

func writeCert(w http.ResponseWriter, certPEM string, der bool) error {
	if !der {
		w.Header().Set("Content-Type", "application/x-pem-file")
		_, err := w.Write([]byte(certPEM))
		return err
	}
	block, _ := pem.Decode([]byte(certPEM))
	w.Header().Set("Content-Type", "application/pkix-cert")
	_, err := w.Write(block.Bytes)
	return err
}

func (t *Routes) bundle(w http.ResponseWriter, r *http.Request) {
	hash := chi.URLParam(r, "hash")
	if !bundlePattern.MatchString(hash) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/x-tar")
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeFile(w, r, t.Store.BundlePath(hash))
}

// submission is Epic's review bundle.
func (t *Routes) submission(w http.ResponseWriter, r *http.Request) error {
	ca, err := t.Store.Active(r.Context())
	if errors.Is(err, ErrNoCA) {
		return rest.Conflict("no_ca", "Create the NixlyOS CA first")
	}
	if err != nil {
		return err
	}
	block, _ := pem.Decode([]byte(ca.CertPEM))
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", `attachment; filename="nixlyos-epic-submission.zip"`)
	archive := zip.NewWriter(w)
	summary, err := json.MarshalIndent(policy(ca), "", "  ")
	if err != nil {
		return err
	}
	for _, file := range []struct {
		name string
		data []byte
	}{
		{"nixlyos-ca.pem", []byte(ca.CertPEM)},
		{"nixlyos-ca.der", block.Bytes},
		{"policy.json", summary},
	} {
		entry, err := archive.CreateHeader(&zip.FileHeader{Name: file.name, Method: zip.Deflate, Modified: time.Unix(0, 0)})
		if err != nil {
			return err
		}
		if _, err := entry.Write(file.data); err != nil {
			return err
		}
	}
	return archive.Close()
}
