package signing

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// UEFI firmware must accept RSA-2048.
	keyBits  = 2048
	validity = 10 * 365 * 24 * time.Hour
)

// ErrNoCA blocks signing without a CA.
var ErrNoCA = errors.New("no NixlyOS CA: create one on the Trust page")

// ErrIncomplete means a file went unsigned.
var ErrIncomplete = errors.New("signature bundle is incomplete")

// CA signs every boot artifact.
type CA struct {
	ID          int64      `json:"id"`
	Subject     string     `json:"subject"`
	Fingerprint string     `json:"fingerprint"`
	CertPEM     string     `json:"certPem"`
	NotAfter    time.Time  `json:"notAfter"`
	CreatedAt   time.Time  `json:"createdAt"`
	RetiredAt   *time.Time `json:"retiredAt"`
}

// Store keeps keys off the database.
type Store struct {
	db           *pgxpool.Pool
	dir          string
	microsoftDir string
}

func NewStore(db *pgxpool.Pool, dir, microsoftDir string) *Store {
	return &Store{db: db, dir: dir, microsoftDir: microsoftDir}
}

const caColumns = `id, subject, fingerprint, cert_pem, not_after, created_at, retired_at`

func (s *Store) Active(ctx context.Context) (CA, error) {
	rows, err := s.db.Query(ctx, `SELECT `+caColumns+` FROM signing_cas WHERE retired_at IS NULL`)
	if err != nil {
		return CA{}, err
	}
	ca, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByPos[CA])
	if errors.Is(err, pgx.ErrNoRows) {
		return CA{}, ErrNoCA
	}
	return ca, err
}

func (s *Store) List(ctx context.Context) ([]CA, error) {
	rows, err := s.db.Query(ctx, `SELECT `+caColumns+` FROM signing_cas ORDER BY id DESC`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[CA])
}

// Create replaces the active CA.
func (s *Store) Create(ctx context.Context) (CA, error) {
	key, err := rsa.GenerateKey(rand.Reader, keyBits)
	if err != nil {
		return CA{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 127))
	if err != nil {
		return CA{}, err
	}
	now := time.Now().UTC()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "NixlyOS Secure Boot CA " + now.Format(time.DateOnly), Organization: []string{"NixlyOS"}},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(validity),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageCodeSigning},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return CA{}, err
	}
	sum := sha256.Sum256(der)
	ca := CA{
		Subject:     template.Subject.CommonName,
		Fingerprint: hex.EncodeToString(sum[:]),
		CertPEM:     string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})),
		NotAfter:    template.NotAfter,
	}
	if err := s.writeKey(ca.Fingerprint, key); err != nil {
		return CA{}, err
	}
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE signing_cas SET retired_at = now() WHERE retired_at IS NULL`); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `
			INSERT INTO signing_cas (subject, fingerprint, cert_pem, not_after) VALUES ($1, $2, $3, $4)
			RETURNING id, created_at`, ca.Subject, ca.Fingerprint, ca.CertPEM, ca.NotAfter).Scan(&ca.ID, &ca.CreatedAt)
	})
	return ca, err
}

// KeyPath is private to the panel.
func (s *Store) KeyPath(ca CA) string {
	return filepath.Join(s.dir, ca.Fingerprint+".key")
}

func (s *Store) writeKey(fingerprint string, key *rsa.PrivateKey) error {
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(s.dir, fingerprint+".key"), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600)
}
