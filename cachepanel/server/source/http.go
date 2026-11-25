package source

import (
	"compress/gzip"
	"io"
	"net/http"

	"cachepanel/rest"
)

// servicePreamble opens a protocol v0 advertisement.
const servicePreamble = "001e# service=git-upload-pack\n0000"

var errEncoding = rest.BadRequest("invalid_encoding", "The request body is not valid gzip")

// Handler serves read-only clones.
func (r *Repo) Handler() http.Handler {
	routes := http.NewServeMux()
	routes.Handle("GET /"+repoName+"/info/refs", rest.Handle(r.advertise))
	routes.Handle("POST /"+repoName+"/git-upload-pack", rest.Handle(r.uploadPack))
	return routes
}

func (r *Repo) advertise(w http.ResponseWriter, req *http.Request) error {
	if req.URL.Query().Get("service") != "git-upload-pack" {
		return rest.NotFound()
	}
	env := protocol(req)
	w.Header().Set("Content-Type", "application/x-git-upload-pack-advertisement")
	w.Header().Set("Cache-Control", "no-cache")
	if len(env) == 0 {
		if _, err := io.WriteString(w, servicePreamble); err != nil {
			return err
		}
	}
	return r.stream(req.Context(), w, call{args: []string{"upload-pack", "--stateless-rpc", "--http-backend-info-refs", "."}, env: env})
}

func (r *Repo) uploadPack(w http.ResponseWriter, req *http.Request) error {
	body := io.Reader(req.Body)
	if req.Header.Get("Content-Encoding") == "gzip" {
		unpacked, err := gzip.NewReader(req.Body)
		if err != nil {
			return errEncoding
		}
		body = unpacked
	}
	w.Header().Set("Content-Type", "application/x-git-upload-pack-result")
	w.Header().Set("Cache-Control", "no-cache")
	return r.stream(req.Context(), w, call{args: []string{"upload-pack", "--stateless-rpc", "."}, stdin: body, env: protocol(req)})
}

// protocol forwards v2 requests.
func protocol(req *http.Request) []string {
	if req.Header.Get("Git-Protocol") != "version=2" {
		return nil
	}
	return []string{"GIT_PROTOCOL=version=2"}
}
