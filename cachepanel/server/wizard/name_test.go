package wizard

import "testing"

func TestGuess(t *testing.T) {
	cases := []struct{ url, file, name, version string }{
		{"https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz", "hello-2.12.1.tar.gz", "hello", "2.12.1"},
		{"https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-x86_64.appimage", "nvim-linux-x86_64.appimage", "nvim", "0.11.4"},
		{"https://github.com/sharkdp/bat/releases/download/v0.25.0/bat_0.25.0_amd64.deb", "bat_0.25.0_amd64.deb", "bat", "0.25.0"},
		{"https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64", "yq_linux_amd64", "yq", "4.44.3"},
		{"https://x.org/Obsidian-1.7.7.AppImage", "Obsidian-1.7.7.AppImage", "obsidian", "1.7.7"},
		{"https://x.org/zellij-x86_64-unknown-linux-musl.tar.gz", "zellij-x86_64-unknown-linux-musl.tar.gz", "zellij", "0"},
	}
	for _, c := range cases {
		if name, version := guessName(c.file), guessVersion(c.url, c.file); name != c.name || version != c.version {
			t.Errorf("%s: got %s %s, want %s %s", c.file, name, version, c.name, c.version)
		}
	}
}
