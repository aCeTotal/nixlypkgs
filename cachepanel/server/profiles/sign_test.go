package profiles

import "testing"

func TestSigningNixMapsPackages(t *testing.T) {
	bundle := "5050d80d22ecd471ea55df7034042c1e041341ff4066e7f6ff38e20b720df8ea"
	got := signingNix("https://cache.aceclan.no", map[string]string{"b-modules": bundle, "a-linux": bundle})
	want := `{
  "a-linux" = {
    url = "https://cache.aceclan.no/api/v1/signatures/` + bundle + `.tar";
    hash = "sha256-UFDYDSLs1HHqVd9wNAQsHgQTQf9AZuf2/zjiC3IN+Oo=";
  };
  "b-modules" = {
    url = "https://cache.aceclan.no/api/v1/signatures/` + bundle + `.tar";
    hash = "sha256-UFDYDSLs1HHqVd9wNAQsHgQTQf9AZuf2/zjiC3IN+Oo=";
  };
}
`
	if got != want {
		t.Errorf("signing.nix:\n%s\nwant:\n%s", got, want)
	}
}
