package pkgbuild

import "testing"

func TestParseEntry(t *testing.T) {
	cases := []struct {
		line string
		want Entry
	}{
		{"cava-0.10.4.tar.gz::https://github.com/karlstav/cava/archive/0.10.4.tar.gz",
			Entry{Name: "cava-0.10.4.tar.gz", URL: "https://github.com/karlstav/cava/archive/0.10.4.tar.gz"}},
		{"https://example.org/foo-1.0.tar.xz", Entry{Name: "foo-1.0.tar.xz", URL: "https://example.org/foo-1.0.tar.xz"}},
		{"git+https://github.com/foo/bar.git#tag=v1.2?signed", Entry{Name: "bar", URL: "https://github.com/foo/bar.git", Git: true, Rev: "v1.2"}},
		{"src::git+https://gitlab.com/a/b.git#branch=dev", Entry{Name: "src", URL: "https://gitlab.com/a/b.git", Git: true, Branch: "dev"}},
		{"git+https://github.com/foo/bar?signed#commit=abc", Entry{Name: "bar", URL: "https://github.com/foo/bar", Git: true, Rev: "abc"}},
		{"fix-build.patch", Entry{Name: "fix-build.patch", Local: true}},
		{"https://example.org/get?id=1&x=2", Entry{Name: "get?id=1_x=2", URL: "https://example.org/get?id=1&x=2"}},
	}
	for _, c := range cases {
		got, err := ParseEntry(c.line)
		if err != nil || got != c.want {
			t.Errorf("ParseEntry(%q) = %+v, %v; want %+v", c.line, got, err, c.want)
		}
	}
	if _, err := ParseEntry("hg+https://example.org/repo"); err == nil {
		t.Error("hg accepted")
	}
}

func TestParseInfo(t *testing.T) {
	info := parseInfo("pkgbase = foo\npkgname = foo\npkgname = foo-docs\npkgver = 1.0\ndepends = a\ndepends = b\nfunction = package_foo\nfunction = build\npkgdesc = \n")
	if info.Base != "foo" || len(info.Names) != 2 || info.Version != "1.0" || len(info.Depends) != 2 || info.Description != "" {
		t.Fatalf("parseInfo = %+v", info)
	}
	if !info.Has("build") || len(info.Splits()) != 1 {
		t.Fatalf("functions = %v", info.Functions)
	}
}
