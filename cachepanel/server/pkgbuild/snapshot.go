package pkgbuild

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strings"
	"time"
)

// Origin is a PKGBUILD repository.
type Origin string

const (
	AUR  Origin = "aur"
	Arch Origin = "arch"
)

const (
	fetchTimeout  = 2 * time.Minute
	snapshotLimit = 32 << 20
	fileLimit     = 500
	userAgent     = "nixly-cachepanel"
)

var (
	client        = &http.Client{Timeout: fetchTimeout}
	errNotFound   = errors.New("no package with that name")
	errTooLarge   = errors.New("the package files are too large")
	projectUnsafe = regexp.MustCompile(`[^a-zA-Z0-9_.-]`)
	projectRuns   = regexp.MustCompile(`[_-]{2,}`)
)

// Fetch downloads build files by name.
func Fetch(ctx context.Context, origin Origin, name string) (map[string][]byte, error) {
	switch origin {
	case AUR:
		var found struct {
			Results []struct{ PackageBase string }
		}
		if err := getJSON(ctx, "https://aur.archlinux.org/rpc/v5/info?arg[]="+url.QueryEscape(name), &found); err != nil {
			return nil, err
		}
		if len(found.Results) == 0 {
			return nil, errNotFound
		}
		base := found.Results[0].PackageBase
		return snapshot(ctx, "https://aur.archlinux.org/cgit/aur.git/snapshot/"+url.PathEscape(base)+".tar.gz")
	case Arch:
		var found struct {
			Results []struct{ Pkgbase string }
		}
		if err := getJSON(ctx, "https://archlinux.org/packages/search/json/?name="+url.QueryEscape(name), &found); err != nil {
			return nil, err
		}
		if len(found.Results) == 0 {
			return nil, errNotFound
		}
		project := gitlabProject(found.Results[0].Pkgbase)
		return snapshot(ctx, "https://gitlab.archlinux.org/archlinux/packaging/packages/"+project+"/-/archive/main/"+project+"-main.tar.gz")
	}
	return nil, fmt.Errorf("unknown source %q", origin)
}

// gitlabProject follows pkgctl's project naming.
func gitlabProject(pkgbase string) string {
	if pkgbase == "tree" {
		return "unix-tree"
	}
	name := strings.ReplaceAll(pkgbase, "+", "plus")
	name = projectUnsafe.ReplaceAllString(name, "-")
	return projectRuns.ReplaceAllString(name, "-")
}

func get(ctx context.Context, address string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, address, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode == http.StatusNotFound {
		_ = res.Body.Close()
		return nil, errNotFound
	}
	if res.StatusCode != http.StatusOK {
		_ = res.Body.Close()
		return nil, fmt.Errorf("%s svarte %s", address, res.Status)
	}
	return res, nil
}

func getJSON(ctx context.Context, address string, into any) error {
	res, err := get(ctx, address)
	if err != nil {
		return err
	}
	defer func() { _ = res.Body.Close() }()
	return json.NewDecoder(io.LimitReader(res.Body, snapshotLimit)).Decode(into)
}

// snapshot keeps top-level regular files.
func snapshot(ctx context.Context, address string) (map[string][]byte, error) {
	res, err := get(ctx, address)
	if err != nil {
		return nil, err
	}
	defer func() { _ = res.Body.Close() }()
	unzipped, err := gzip.NewReader(io.LimitReader(res.Body, snapshotLimit))
	if err != nil {
		return nil, err
	}
	files := map[string][]byte{}
	archive := tar.NewReader(unzipped)
	total := 0
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			return files, nil
		}
		if err != nil {
			return nil, err
		}
		_, name, nested := strings.Cut(header.Name, "/")
		if header.Typeflag != tar.TypeReg || !nested || strings.Contains(name, "/") || strings.HasPrefix(name, ".") {
			continue
		}
		total += int(header.Size)
		if total > snapshotLimit || len(files) >= fileLimit {
			return nil, errTooLarge
		}
		content, err := io.ReadAll(archive)
		if err != nil {
			return nil, err
		}
		files[path.Base(name)] = content
	}
}
