package source

import (
	"encoding/base64"
	"testing"
)

func TestParseKey(t *testing.T) {
	blob := append([]byte{0, 0, 0, 11}, "ssh-ed25519"...)
	blob = append(blob, make([]byte, 36)...)
	line := "ssh-ed25519 " + base64.StdEncoding.EncodeToString(blob) + " me@host"
	key, err := parseKey(line)
	if err != nil {
		t.Fatal(err)
	}
	if key.Type != "ssh-ed25519" || key.Fingerprint[:7] != "SHA256:" {
		t.Fatalf("parsed %+v", key)
	}
	mismatched := "ssh-rsa " + base64.StdEncoding.EncodeToString(blob)
	for _, bad := range []string{"", "ssh-ed25519", "ssh-dss AAAA", "ssh-ed25519 !!!", mismatched, "ssh-ed25519 AAAA"} {
		if _, err := parseKey(bad); err == nil {
			t.Errorf("parseKey(%q) accepted", bad)
		}
	}
}
