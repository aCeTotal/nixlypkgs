package source

import (
	"net/http"
	"net/http/cgi"
	"os/exec"
	"path/filepath"

	"cachepanel/rest"
)

// Handler serves clones and fetches, never pushes.
func (r *Repo) Handler() (http.Handler, error) {
	git, err := exec.LookPath("git")
	if err != nil {
		return nil, err
	}
	backend := &cgi.Handler{
		Path: git,
		Args: []string{"http-backend"},
		Env:  []string{"GIT_PROJECT_ROOT=" + filepath.Dir(r.dir), "GIT_HTTP_EXPORT_ALL=1"},
	}
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if !readOnly(req) {
			rest.WriteError(w, req, rest.NotFound())
			return
		}
		backend.ServeHTTP(w, req)
	}), nil
}

func readOnly(r *http.Request) bool {
	switch r.URL.Path {
	case "/" + repoName + "/info/refs":
		return r.Method == http.MethodGet && r.URL.Query().Get("service") == "git-upload-pack"
	case "/" + repoName + "/git-upload-pack":
		return r.Method == http.MethodPost
	}
	return false
}
