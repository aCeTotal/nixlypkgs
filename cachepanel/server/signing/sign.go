package signing

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"golang.org/x/sync/errgroup"
)

// Kind selects the signature format.
type Kind string

const (
	Module Kind = "module"
	EFI    Kind = "efi"
)

// File is one verified artifact.
type File struct {
	Path    string
	Hash    string
	Kind    Kind
	Package string
}

// Signed maps packages to bundles.
type Signed struct {
	CA      int64
	Bundles map[string]string
}

// Sign signs what is missing.
func (s *Store) Sign(ctx context.Context, toplevels []string, files []File) (Signed, error) {
	ca, err := s.Active(ctx)
	if err != nil {
		return Signed{}, err
	}
	if err := Trusts(ca, toplevels); err != nil {
		return Signed{}, err
	}
	missing, err := s.unsigned(ctx, ca, files)
	if err != nil {
		return Signed{}, err
	}
	signatures := make([][]byte, len(missing))
	group, groupCtx := errgroup.WithContext(ctx)
	group.SetLimit(runtime.NumCPU())
	for i, file := range missing {
		group.Go(func() error {
			signature, err := s.signFile(groupCtx, ca, file)
			signatures[i] = signature
			return err
		})
	}
	if err := group.Wait(); err != nil {
		return Signed{}, err
	}
	if err := s.record(ctx, ca, missing, signatures); err != nil {
		return Signed{}, err
	}
	return s.bundle(ctx, ca, files)
}

func (s *Store) unsigned(ctx context.Context, ca CA, files []File) ([]File, error) {
	hashes := make([]string, len(files))
	for i, file := range files {
		hashes[i] = file.Hash
	}
	rows, err := s.db.Query(ctx, `SELECT file_hash FROM signatures WHERE ca_id = $1 AND file_hash = ANY($2)`, ca.ID, hashes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	signed := map[string]bool{}
	for rows.Next() {
		var hash string
		if err := rows.Scan(&hash); err != nil {
			return nil, err
		}
		signed[hash] = true
	}
	var missing []File
	for _, file := range files {
		if !signed[file.Hash] {
			signed[file.Hash] = true
			missing = append(missing, file)
		}
	}
	return missing, rows.Err()
}

func (s *Store) record(ctx context.Context, ca CA, files []File, signatures [][]byte) error {
	if len(files) == 0 {
		return nil
	}
	hashes, kinds := make([]string, len(files)), make([]string, len(files))
	for i, file := range files {
		hashes[i], kinds[i] = file.Hash, string(file.Kind)
	}
	_, err := s.db.Exec(ctx, `
		INSERT INTO signatures (file_hash, ca_id, kind, signature)
		SELECT h, $1, k::signature_kind, sig FROM unnest($2::text[], $3::text[], $4::bytea[]) AS t(h, k, sig)
		ON CONFLICT DO NOTHING`, ca.ID, hashes, kinds, signatures)
	return err
}

// signFile mirrors sign-file and sbsign.
func (s *Store) signFile(ctx context.Context, ca CA, file File) ([]byte, error) {
	cert, err := s.certPath(ca)
	if err != nil {
		return nil, err
	}
	if file.Kind == Module {
		return run(ctx, "openssl", "cms", "-sign", "-binary", "-noattr", "-nocerts", "-nosmimecap",
			"-md", "sha512", "-outform", "DER", "-signer", cert, "-inkey", s.KeyPath(ca), "-in", file.Path)
	}
	out, err := os.CreateTemp("", "nixly-efi-*.sig")
	if err != nil {
		return nil, err
	}
	defer os.Remove(out.Name())
	if err := out.Close(); err != nil {
		return nil, err
	}
	if _, err := run(ctx, "sbsign", "--detached", "--key", s.KeyPath(ca), "--cert", cert, "--output", out.Name(), file.Path); err != nil {
		return nil, err
	}
	return os.ReadFile(out.Name())
}

func (s *Store) certPath(ca CA) (string, error) {
	path := filepath.Join(s.dir, ca.Fingerprint+".pem")
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}
	return path, os.WriteFile(path, []byte(ca.CertPEM), 0o644)
}

func run(ctx context.Context, name string, args ...string) ([]byte, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%s: %w: %s", name, err, stderr.String())
	}
	return stdout.Bytes(), nil
}
