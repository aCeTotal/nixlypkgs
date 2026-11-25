package signing

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func TestSignatureListLayout(t *testing.T) {
	want := []byte{0xa1, 0x59, 0xc0, 0xa5, 0xe4, 0x94, 0xa7, 0x4a, 0x87, 0xb5, 0xab, 0x15, 0x5c, 0x2b, 0xf0, 0x72}
	if !bytes.Equal(x509Type[:], want) {
		t.Fatalf("EFI_CERT_X509_GUID = % x, want % x", x509Type, want)
	}
	der := []byte("certificate")
	list, err := signatureList(Cert{guid: microsoftOwner, der: der})
	if err != nil {
		t.Fatal(err)
	}
	if size := binary.LittleEndian.Uint32(list[16:]); int(size) != len(list) {
		t.Errorf("SignatureListSize = %d, want %d", size, len(list))
	}
	if size := binary.LittleEndian.Uint32(list[24:]); int(size) != ownerLength+len(der) {
		t.Errorf("SignatureSize = %d, want %d", size, ownerLength+len(der))
	}
	if !bytes.Equal(list[listHeader:listHeader+ownerLength], microsoftOwner[:]) || !bytes.HasSuffix(list, der) {
		t.Error("owner or certificate misplaced")
	}
}
