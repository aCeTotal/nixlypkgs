package source

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"slices"
	"strings"

	"cachepanel/rest"
)

var (
	keyTypes = []string{
		"ssh-ed25519", "sk-ssh-ed25519@openssh.com",
		"ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "sk-ecdsa-sha2-nistp256@openssh.com",
		"ssh-rsa",
	}
	errKey = rest.Unprocessable("invalid_key", "Paste an OpenSSH public key, like the contents of ~/.ssh/id_ed25519.pub")
)

// publicKey is one parsed authorized key.
type publicKey struct {
	Type        string
	Data        string
	Fingerprint string
}

// parseKey checks the blob names its type.
func parseKey(line string) (publicKey, error) {
	fields := strings.Fields(line)
	if len(fields) < 2 || !slices.Contains(keyTypes, fields[0]) {
		return publicKey{}, errKey
	}
	blob, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil || len(blob) < 4 {
		return publicKey{}, errKey
	}
	size := binary.BigEndian.Uint32(blob)
	if uint64(size) > uint64(len(blob)-4) || string(blob[4:4+size]) != fields[0] {
		return publicKey{}, errKey
	}
	sum := sha256.Sum256(blob)
	return publicKey{
		Type:        fields[0],
		Data:        fields[1],
		Fingerprint: "SHA256:" + base64.RawStdEncoding.EncodeToString(sum[:]),
	}, nil
}
