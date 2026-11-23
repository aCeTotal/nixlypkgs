package signing

import (
	"context"
	"crypto/x509"
	"encoding/binary"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Variable is a Secure Boot database.
type Variable string

const (
	PK  Variable = "PK"
	KEK Variable = "KEK"
	DB  Variable = "db"
)

// Variables in enrollment order.
var Variables = []Variable{PK, KEK, DB}

// SetupMode names firmware without keys.
const SetupMode = "setup"

// ErrUnknownCA rejects foreign platform keys.
var ErrUnknownCA = errors.New("the machine's platform key is not a NixlyOS CA")

const (
	efiTime     = "2006-01-02 15:04:05"
	listHeader  = 28
	ownerLength = 16
)

var (
	x509Type       = guid("a5c059a1-94e4-4aa7-87b5-ab155c2bf072")
	nixlyOwner     = guid("3b0a8e5c-7f2d-4c51-9a6e-1d52c48b37e0")
	microsoftOwner = guid("77fa9abd-0359-4d32-bd60-28f4e78f784b")
)

// Cert is one database entry.
type Cert struct {
	Subject string `json:"subject"`
	Owner   string `json:"owner"`
	guid    [16]byte
	der     []byte
}

// Database is what one variable holds.
type Database struct {
	Variable Variable `json:"variable"`
	Certs    []Cert   `json:"certs"`
}

// Firmware lists the active key databases.
func (s *Store) Firmware(ctx context.Context) ([]Database, error) {
	active, err := s.Active(ctx)
	if err != nil {
		return nil, err
	}
	previous, err := s.previous(ctx)
	if err != nil {
		return nil, err
	}
	nixly := []Cert{nixlyCert(active)}
	trusted := nixly
	if previous != nil {
		trusted = []Cert{nixly[0], nixlyCert(*previous)}
	}
	keks, err := s.microsoft("KEK")
	if err != nil {
		return nil, err
	}
	dbs, err := s.microsoft("db")
	if err != nil {
		return nil, err
	}
	return []Database{
		{PK, nixly},
		{KEK, append(nixly, keks...)},
		{DB, append(trusted, dbs...)},
	}, nil
}

// Update moves firmware to the active CA.
func (s *Store) Update(ctx context.Context, from string, variable Variable) ([]byte, error) {
	signer, err := s.signer(ctx, from)
	if err != nil {
		return nil, err
	}
	databases, err := s.Firmware(ctx)
	if err != nil {
		return nil, err
	}
	var list []byte
	for _, database := range databases {
		if database.Variable != variable {
			continue
		}
		for _, cert := range database.Certs {
			list = append(list, signatureList(cert)...)
		}
	}
	work, err := os.MkdirTemp("", "nixly-firmware-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(work)
	in, out := filepath.Join(work, "list.esl"), filepath.Join(work, "update.auth")
	if err := os.WriteFile(in, list, 0o600); err != nil {
		return nil, err
	}
	cert, err := s.certPath(signer)
	if err != nil {
		return nil, err
	}
	if _, err := run(ctx, "sign-efi-sig-list", "-t", time.Now().UTC().Format(efiTime), "-k", s.KeyPath(signer), "-c", cert,
		string(variable), in, out); err != nil {
		return nil, err
	}
	return os.ReadFile(out)
}

// Setup mode self-signs.
func (s *Store) signer(ctx context.Context, from string) (CA, error) {
	if from == SetupMode {
		return s.Active(ctx)
	}
	rows, err := s.db.Query(ctx, `SELECT `+caColumns+` FROM signing_cas WHERE fingerprint = $1`, from)
	if err != nil {
		return CA{}, err
	}
	ca, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByPos[CA])
	if errors.Is(err, pgx.ErrNoRows) {
		return CA{}, ErrUnknownCA
	}
	return ca, err
}

// Old releases keep booting after rotation.
func (s *Store) previous(ctx context.Context) (*CA, error) {
	rows, err := s.db.Query(ctx, `SELECT `+caColumns+` FROM signing_cas WHERE retired_at IS NOT NULL ORDER BY retired_at DESC LIMIT 1`)
	if err != nil {
		return nil, err
	}
	ca, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByPos[CA])
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return &ca, err
}

// GPU option ROMs need Microsoft's keys.
func (s *Store) microsoft(variable string) ([]Cert, error) {
	paths, err := filepath.Glob(filepath.Join(s.microsoftDir, variable, "*.der"))
	if err != nil {
		return nil, err
	}
	if len(paths) == 0 {
		return nil, errors.New("no Microsoft " + variable + " certificates in " + s.microsoftDir)
	}
	certs := make([]Cert, len(paths))
	for i, path := range paths {
		der, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		parsed, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, err
		}
		certs[i] = Cert{Subject: parsed.Subject.CommonName, Owner: "Microsoft", guid: microsoftOwner, der: der}
	}
	return certs, nil
}

func nixlyCert(ca CA) Cert {
	block, _ := pem.Decode([]byte(ca.CertPEM))
	return Cert{Subject: ca.Subject, Owner: "NixlyOS", guid: nixlyOwner, der: block.Bytes}
}

// signatureList is one EFI_SIGNATURE_LIST.
func signatureList(cert Cert) []byte {
	list := make([]byte, listHeader+ownerLength+len(cert.der))
	copy(list, x509Type[:])
	binary.LittleEndian.PutUint32(list[16:], uint32(len(list)))
	binary.LittleEndian.PutUint32(list[24:], uint32(ownerLength+len(cert.der)))
	copy(list[listHeader:], cert.guid[:])
	copy(list[listHeader+ownerLength:], cert.der)
	return list
}

// guid encodes the mixed-endian EFI layout.
func guid(text string) [16]byte {
	raw, err := hex.DecodeString(strings.ReplaceAll(text, "-", ""))
	if err != nil || len(raw) != 16 {
		panic("bad guid " + text)
	}
	var out [16]byte
	binary.LittleEndian.PutUint32(out[0:], binary.BigEndian.Uint32(raw[0:]))
	binary.LittleEndian.PutUint16(out[4:], binary.BigEndian.Uint16(raw[4:]))
	binary.LittleEndian.PutUint16(out[6:], binary.BigEndian.Uint16(raw[6:]))
	copy(out[8:], raw[8:])
	return out
}
