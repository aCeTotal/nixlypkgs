package recipe

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"slices"
	"time"
)

const formatTimeout = 30 * time.Second

const (
	linux = "lib.platforms.linux"
	x86   = `[ "x86_64-linux" ]`
)

var renderers = map[Builder]func(*writer, Spec){
	CMake:     compiled,
	Meson:     compiled,
	Autotools: compiled,
	Make:      compiled,
	Cargo:     cargo,
	Go:        goModule,
	Python:    python,
	Npm:       npm,
	AppImage:  appImage,
	Deb:       prebuilt,
	Rpm:       prebuilt,
	Prebuilt:  prebuilt,
	Makepkg:   makepkg,
}

// Render writes default.nix for a spec.
func Render(s Spec) (string, error) {
	render, ok := renderers[s.Builder]
	if !ok {
		return "", fmt.Errorf("ukjent byggemetode %q", s.Builder)
	}
	w := newWriter()
	render(w, s)
	return w.header() + w.b.String(), nil
}

// Format runs nixfmt over rendered source.
func Format(ctx context.Context, source string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, formatTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nixfmt")
	cmd.Stdin = bytes.NewBufferString(source)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("nixfmt: %w: %s", err, stderr.String())
	}
	return string(out), nil
}

// with appends required attrs.
func with(list []string, required ...string) []string {
	for _, attr := range required {
		if !slices.Contains(list, attr) {
			list = append(list, attr)
		}
	}
	return list
}

func (w *writer) head(s Spec) {
	w.str("pname", s.Pname)
	w.str("version", s.Version)
}
