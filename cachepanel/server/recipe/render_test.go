package recipe

import (
	"context"
	"os/exec"
	"strings"
	"testing"
)

func sample(builder Builder) Spec {
	return Spec{
		Attr: "demo", Pname: "demo", Version: "1.2.0", Builder: builder,
		Sources: []Source{{Kind: URL, URL: "https://example.org/demo-1.2.0.tar.gz", Hash: "sha256-CUXcXPRqNylZ0BeI8SZiQPnUqIpuEjAoqn59Hpb9oBs="}},
		Native:  []string{"pkg-config"}, Inputs: []string{"python3Packages.requests", "qt6.qtbase"},
		Meta: Meta{Description: `Says "${hi}"`, Homepage: "https://example.org", License: "mit", MainProgram: "demo"},
	}
}

func TestRenderParses(t *testing.T) {
	if _, err := exec.LookPath("nixfmt"); err != nil {
		t.Skip("nixfmt missing")
	}
	specs := map[string]Spec{}
	for builder := range renderers {
		specs[string(builder)] = sample(builder)
	}
	electron := sample(Deb)
	electron.Layout = Layout{Mode: FHSLayout, Dirs: []string{"usr", "opt"}, Electron: true,
		Programs: []Program{{Name: "demo", Path: "opt/Demo App/demo"}},
		Desktops: []Desktop{{Path: "share/applications/demo.desktop", Rewrite: []Rewrite{
			{From: "/opt/Demo App/demo", To: "demo"}, {From: "/opt/Demo App/icon.png", To: "$out/opt/Demo App/icon.png"}}}}}
	specs["electron"] = electron
	image := sample(AppImage)
	image.Layout = Layout{Desktops: []Desktop{{Path: "demo.desktop", Rewrite: []Rewrite{{From: "Exec=AppRun", To: "Exec=demo"}}}},
		Icons: []string{"usr/share/icons", "demo.png"}}
	specs["appimage-layout"] = image
	pkg := sample(Makepkg)
	pkg.Sources = append(pkg.Sources, Source{Kind: File, Name: "fix.patch"}, Source{Kind: GitHub, Name: "demo", Owner: "o", Repo: "demo", Rev: "v1.2.0"})
	pkg.Vendor = CargoVendor
	specs["makepkg-git"] = pkg
	for name, spec := range specs {
		source, err := Render(spec)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		formatted, err := Format(context.Background(), source)
		if err != nil {
			t.Fatalf("%s: %v\n%s", name, err, source)
		}
		if !strings.Contains(formatted, `\${hi}`) {
			t.Errorf("%s: description not escaped:\n%s", name, formatted)
		}
	}
}

func TestPlaceholderDistinct(t *testing.T) {
	if Placeholder(1) == Placeholder(VendorSlot) || len(Placeholder(1)) != len("sha256-")+44 {
		t.Fatal(Placeholder(1))
	}
}

func TestValidate(t *testing.T) {
	spec := sample(CMake)
	if err := spec.Validate(); err != nil {
		t.Fatal(err)
	}
	spec.Sources = append(spec.Sources, Source{Kind: File, Name: "../etc/passwd"})
	if spec.Validate() == nil {
		t.Error("path traversal accepted")
	}
	spec = sample(CMake)
	spec.Meta.License = "mit; builtins.readFile"
	if spec.Validate() == nil {
		t.Error("license injection accepted")
	}
}
