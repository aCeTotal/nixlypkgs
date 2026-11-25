package signing

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"io/fs"
	"os"
	"path"
)

// ErrUntrusted means kernels lack the CA.
var ErrUntrusted = errors.New("the kernel does not trust the active NixlyOS CA yet: update the nixlyos-ca input")

// Trusts checks kernels embed the CA.
func Trusts(ca CA, toplevels []string) error {
	for _, toplevel := range toplevels {
		rel, err := inStore(toplevel)
		if err != nil {
			return err
		}
		data, err := fs.ReadFile(os.DirFS(storeDir), path.Join(rel, "nixlyos-ca.pem"))
		if err != nil {
			return ErrUntrusted
		}
		block, _ := pem.Decode(data)
		if block == nil {
			return ErrUntrusted
		}
		sum := sha256.Sum256(block.Bytes)
		if hex.EncodeToString(sum[:]) != ca.Fingerprint {
			return ErrUntrusted
		}
	}
	return nil
}
