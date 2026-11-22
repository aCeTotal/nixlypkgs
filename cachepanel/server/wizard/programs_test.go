package wizard

import (
	"cmp"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"cachepanel/recipe"
)

const smokeTimeout = 30 * time.Second

// program is one real import case.
type program struct {
	name    string
	request Request
	builder recipe.Builder
	// smoke runs from bin; empty skips.
	smoke []string
}

var programs = []program{
	{"aur-autotools-git", Request{Origin: FromAUR, Name: "cava-git"}, recipe.Makepkg, []string{"cava", "-v"}},
	{"aur-make", Request{Origin: FromAUR, Name: "cbonsai"}, recipe.Makepkg, []string{"cbonsai", "--help"}},
	{"aur-cmake", Request{Origin: FromAUR, Name: "peaclock"}, recipe.Makepkg, []string{"peaclock", "--version"}},
	{"aur-deb-bin", Request{Origin: FromAUR, Name: "spotify"}, recipe.Makepkg, nil},
	{"aur-git", Request{Origin: FromAUR, Name: "cmatrix-git"}, recipe.Makepkg, []string{"cmatrix", "-V"}},
	{"aur-go-cgo", Request{Origin: FromAUR, Name: "yay"}, recipe.Makepkg, nil},
	{"aur-script", Request{Origin: FromAUR, Name: "pfetch"}, recipe.Makepkg, nil},
	{"aur-appimage", Request{Origin: FromAUR, Name: "obsidian-appimage"}, recipe.AppImage, nil},
	{"aur-electron-bin", Request{Origin: FromAUR, Name: "visual-studio-code-bin"}, recipe.Makepkg, nil},
	{"arch-autotools", Request{Origin: FromArch, Name: "jq"}, recipe.Makepkg, []string{"jq", "--version"}},
	{"arch-make", Request{Origin: FromArch, Name: "tree"}, recipe.Makepkg, []string{"tree", "--version"}},
	{"arch-go", Request{Origin: FromArch, Name: "fzf"}, recipe.Makepkg, []string{"fzf", "--version"}},
	{"arch-cargo", Request{Origin: FromArch, Name: "ripgrep"}, recipe.Makepkg, []string{"rg", "--version"}},
	{"arch-cmake", Request{Origin: FromArch, Name: "btop"}, recipe.Makepkg, []string{"btop", "--version"}},
	{"arch-meson-wayland", Request{Origin: FromArch, Name: "foot"}, recipe.Makepkg, []string{"foot", "--version"}},
	{"arch-python", Request{Origin: FromArch, Name: "yt-dlp"}, recipe.Makepkg, []string{"yt-dlp", "--version"}},
	{"arch-zig", Request{Origin: FromArch, Name: "ncdu"}, recipe.Makepkg, []string{"ncdu", "--version"}},
	{"arch-tmux", Request{Origin: FromArch, Name: "tmux"}, recipe.Makepkg, []string{"tmux", "-V"}},
	{"url-autotools", Request{Origin: FromURL, URL: "https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz"}, recipe.Autotools, []string{"hello", "--version"}},
	{"github-cargo", Request{Origin: FromGitHub, URL: "https://github.com/sharkdp/hexyl"}, recipe.Cargo, []string{"hexyl", "--version"}},
	{"github-go", Request{Origin: FromGitHub, URL: "https://github.com/charmbracelet/gum"}, recipe.Go, []string{"gum", "--version"}},
	{"github-meson", Request{Origin: FromGitHub, URL: "https://github.com/emersion/slurp"}, recipe.Meson, nil},
	{"github-cmake-lib", Request{Origin: FromGitHub, URL: "https://github.com/DaveGamble/cJSON"}, recipe.CMake, nil},
	{"github-python", Request{Origin: FromGitHub, URL: "https://github.com/httpie/cli"}, recipe.Python, []string{"http", "--version"}},
	{"github-npm", Request{Origin: FromGitHub, URL: "https://github.com/remy/nodemon"}, recipe.Npm, []string{"nodemon", "--version"}},
	{"url-appimage", Request{Origin: FromURL, URL: "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-x86_64.appimage"}, recipe.AppImage, nil},
	{"url-deb", Request{Origin: FromURL, URL: "https://github.com/sharkdp/bat/releases/download/v0.25.0/bat_0.25.0_amd64.deb"}, recipe.Deb, []string{"bat", "--version"}},
	{"url-deb-electron", Request{Origin: FromURL, URL: "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.7.7/obsidian_1.7.7_amd64.deb"}, recipe.Deb, nil},
	{"url-rpm", Request{Origin: FromURL, URL: "https://github.com/fastfetch-cli/fastfetch/releases/download/2.71.0/fastfetch-linux-amd64.rpm"}, recipe.Rpm, []string{"fastfetch", "--version"}},
	{"url-tarball-tree", Request{Origin: FromURL, URL: "https://github.com/cli/cli/releases/download/v2.62.0/gh_2.62.0_linux_amd64.tar.gz"}, recipe.Prebuilt, []string{"gh", "--version"}},
	{"url-single-binary", Request{Origin: FromURL, URL: "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64"}, recipe.Prebuilt, []string{"yq", "--version"}},
	{"url-zip-flat", Request{Origin: FromURL, URL: "https://github.com/denoland/deno/releases/download/v2.1.4/deno-x86_64-unknown-linux-gnu.zip"}, recipe.Prebuilt, []string{"deno", "--version"}},
	{"url-go-archive", Request{Origin: FromURL, URL: "https://github.com/junegunn/fzf/archive/refs/tags/v0.56.0.tar.gz"}, recipe.Go, []string{"fzf", "--version"}},
	{"github-cargo-sys", Request{Origin: FromGitHub, URL: "https://github.com/alacritty/alacritty"}, recipe.Cargo, []string{"alacritty", "--version"}},
	{"github-cmake-app", Request{Origin: FromGitHub, URL: "https://github.com/abishekvashok/cmatrix"}, recipe.CMake, []string{"cmatrix", "-V"}},
	{"arch-qt", Request{Origin: FromArch, Name: "qt6ct"}, recipe.Makepkg, nil},
	{"arch-gtk", Request{Origin: FromArch, Name: "zenity"}, recipe.Makepkg, nil},
	{"upload-autotools", Request{Origin: FromUpload, URL: "https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz"}, recipe.Autotools, []string{"hello", "--version"}},
}

// TestPrograms needs CACHEPANEL_PROGRAMS, a flake ref.
func TestPrograms(t *testing.T) {
	flake := os.Getenv("CACHEPANEL_PROGRAMS")
	if flake == "" {
		t.Skip("CACHEPANEL_PROGRAMS is not set")
	}
	only := os.Getenv("CACHEPANEL_ONLY")
	lab := &Lab{Flake: func(context.Context) (string, error) { return flake, nil }, Uploads: NewUploads(t.TempDir(), "http://localhost")}
	logs, err := os.OpenRoot(cmp.Or(os.Getenv("CACHEPANEL_LOGS"), t.TempDir()))
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range programs {
		if only != "" && !strings.Contains(p.name, only) {
			continue
		}
		t.Run(p.name, func(t *testing.T) {
			t.Parallel()
			ctx := t.Context()
			request := p.request
			if request.Origin == FromUpload {
				request.Upload = upload(t, lab.Uploads, request.URL)
			}
			draft, err := lab.Import(ctx, request)
			if err != nil {
				t.Fatalf("import: %v", err)
			}
			if draft.Spec.Builder != p.builder {
				t.Errorf("builder = %s, want %s", draft.Spec.Builder, p.builder)
			}
			log, err := logs.Create(p.name + ".log")
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = log.Close() }()
			outcome, err := lab.Build(ctx, &draft, "", log)
			source, _ := recipe.Render(draft.Spec)
			_, _ = fmt.Fprintf(log, "\n==> default.nix\n%s\n==> steps %v\n==> hints %v\n==> notes %v\n", source, outcome.Steps, outcome.Hints, draft.Notes)
			if err != nil {
				t.Fatalf("build: %v (steps %v, hints %v); log in %s", err, outcome.Steps, outcome.Hints, log.Name())
			}
			t.Logf("built %s in %d fixes: %v", outcome.Output, len(outcome.Steps), outcome.Steps)
			if len(p.smoke) > 0 {
				smoke(t, outcome.Output, p.smoke, log)
			}
		})
	}
}

func smoke(t *testing.T, output string, command []string, log io.Writer) {
	ctx, cancel := context.WithTimeout(t.Context(), smokeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, filepath.Join(output, "bin", command[0]), command[1:]...)
	cmd.Env = append(os.Environ(), "HOME="+t.TempDir(), "TERM=xterm")
	out, err := cmd.CombinedOutput()
	_, _ = fmt.Fprintf(log, "==> smoke %v\n%s\n", command, out)
	if err != nil {
		t.Fatalf("smoke %v: %v\n%s", command, err, out)
	}
}

// upload saves a download like a user.
func upload(t *testing.T, uploads *Uploads, url string) string {
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	hash, err := uploads.Save(path.Base(url), res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return hash
}
