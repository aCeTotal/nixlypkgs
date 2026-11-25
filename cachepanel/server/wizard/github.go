package wizard

import (
	"context"
	"encoding/json"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

const aboutTimeout = 15 * time.Second

// about is what GitHub says about a repository.
type about struct {
	Description, Homepage, License, Release string
}

// gitHubAbout is best effort, rate-limited.
func gitHubAbout(ctx context.Context, owner, repo string) about {
	ctx, cancel := context.WithTimeout(ctx, aboutTimeout)
	defer cancel()
	var info struct {
		Description string `json:"description"`
		Homepage    string `json:"homepage"`
		License     struct {
			SPDX string `json:"spdx_id"`
		} `json:"license"`
	}
	var release struct {
		Tag string `json:"tag_name"`
	}
	base := "https://api.github.com/repos/" + owner + "/" + repo
	getJSON(ctx, base, &info)
	getJSON(ctx, base+"/releases/latest", &release)
	return about{Description: info.Description, Homepage: info.Homepage, License: info.License.SPDX, Release: release.Tag}
}

func getJSON(ctx context.Context, url string, into any) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode == http.StatusOK {
		_ = json.NewDecoder(res.Body).Decode(into)
	}
}

// followedBranch is the named branch, else the repository's default.
func followedBranch(ctx context.Context, owner, repo, ref string) string {
	if ref != "" && !commitHash.MatchString(ref) {
		return ref
	}
	ctx, cancel := context.WithTimeout(ctx, aboutTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", "ls-remote", "--symref", "https://github.com/"+owner+"/"+repo, "HEAD").Output()
	if err != nil {
		return ""
	}
	head, _, _ := strings.Cut(string(out), "\t")
	branch, found := strings.CutPrefix(head, "ref: refs/heads/")
	if !found {
		return ""
	}
	return branch
}
