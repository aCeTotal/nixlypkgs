package depmap

import (
	"slices"
	"testing"
)

func TestArch(t *testing.T) {
	cases := map[string][]string{
		"libpulse>=15":    {"libpulseaudio"},
		"python-requests": {"python3Packages.requests"},
		"qt6-5compat":     {"qt6.qt5compat"},
		"qt5-svg":         {"libsForQt5.qtsvg"},
		"perl-file-which": {"perlPackages.FileWhich"},
		"cargo":           {"cargo", "rustc"},
		"fftw":            {"fftw"},
		"foo-git":         {"foo"},
	}
	for name, want := range cases {
		if got := Arch(name).Alternatives[0]; !slices.Equal(got, want) {
			t.Errorf("Arch(%q) = %v, want %v", name, got, want)
		}
	}
	for _, name := range []string{"glibc", "lib32-mesa", "ttf-dejavu", "sh"} {
		if !Arch(name).Dropped {
			t.Errorf("Arch(%q) kept", name)
		}
	}
}

func TestSoname(t *testing.T) {
	cases := map[string]string{
		"libgtk-3.so.0":      "gtk3",
		"libQt6Svg.so.6":     "qt6.qtsvg",
		"libQt6Core.so.6":    "qt6.qtbase",
		"libxcb-icccm.so.4":  "xcbutilwm",
		"libxcb-randr.so.0":  "libxcb",
		"libstdc++.so.6":     "stdenv.cc.cc.lib",
		"libssl.so.1.1":      "openssl_1_1",
		"libssl.so.3":        "openssl",
		"libunknownthing.so": "libunknownthing",
	}
	for name, want := range cases {
		if got := Soname(name).Alternatives[0][0]; got != want {
			t.Errorf("Soname(%q) = %v, want %v", name, got, want)
		}
	}
	if !Soname("libcuda.so.1").Dropped {
		t.Error("libcuda kept")
	}
}

func TestPkgConfig(t *testing.T) {
	if got := PkgConfig("gtk+-3.0").Alternatives[0][0]; got != "gtk3" {
		t.Errorf("gtk+-3.0 = %v", got)
	}
	if got := PkgConfig("libportal-gtk4-1").Alternatives; !slices.ContainsFunc(got, func(a []string) bool { return a[0] == "libportal-gtk4" }) {
		t.Errorf("libportal-gtk4-1 = %v", got)
	}
}
