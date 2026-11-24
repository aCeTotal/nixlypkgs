package source

import "testing"

func TestDescribeInputs(t *testing.T) {
	github := describe("linux-src", lockRef{Type: "github", Owner: "CachyOS", Repo: "linux", Ref: "cachyos-7.3.5-2"},
		lockRef{Rev: "1ac42d4f", LastModified: 1795541536})
	if github.Source != "github:CachyOS/linux" || github.Ref != "cachyos-7.3.5-2" || github.Rev != "1ac42d4f" || github.Modified == nil {
		t.Fatalf("github = %+v", github)
	}
	file := describe("nixlyos-ca", lockRef{Type: "file", URL: "https://cache.aceclan.no/api/v1/ca.pem"}, lockRef{})
	if file.Source != "https://cache.aceclan.no/api/v1/ca.pem" || file.Modified != nil {
		t.Fatalf("file = %+v", file)
	}
	if local := describe("extra", lockRef{Type: "path", Path: "/srv/extra"}, lockRef{}); local.Source != "/srv/extra" {
		t.Fatalf("path = %+v", local)
	}
}
