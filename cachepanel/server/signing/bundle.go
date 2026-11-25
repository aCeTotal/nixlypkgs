package signing

import (
	"archive/tar"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"time"
)

var bundlePattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

type signature struct {
	kind  string
	bytes []byte
}

// bundle writes one tar per package.
func (s *Store) bundle(ctx context.Context, ca CA, files []File) (Signed, error) {
	known, err := s.signatures(ctx, ca, files)
	if err != nil {
		return Signed{}, err
	}
	byPackage := map[string][]string{}
	for _, file := range files {
		byPackage[file.Package] = append(byPackage[file.Package], file.Hash)
	}
	signed := Signed{CA: ca.ID, Bundles: make(map[string]string, len(byPackage))}
	for pkg, hashes := range byPackage {
		name, err := s.writeBundle(hashes, known)
		if err != nil {
			return Signed{}, err
		}
		signed.Bundles[pkg] = name
	}
	return signed, nil
}

func (s *Store) signatures(ctx context.Context, ca CA, files []File) (map[string]signature, error) {
	hashes := make([]string, len(files))
	for i, file := range files {
		hashes[i] = file.Hash
	}
	rows, err := s.db.Query(ctx, `SELECT file_hash, kind, signature FROM signatures WHERE ca_id = $1 AND file_hash = ANY($2)`, ca.ID, hashes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	known := make(map[string]signature, len(files))
	for rows.Next() {
		var hash string
		var sig signature
		if err := rows.Scan(&hash, &sig.kind, &sig.bytes); err != nil {
			return nil, err
		}
		known[hash] = sig
	}
	return known, rows.Err()
}

// writeBundle is content-addressed and deterministic.
func (s *Store) writeBundle(hashes []string, known map[string]signature) (string, error) {
	slices.Sort(hashes)
	hashes = slices.Compact(hashes)
	var archive bytes.Buffer
	writer := tar.NewWriter(&archive)
	for _, hash := range hashes {
		sig, found := known[hash]
		if !found {
			return "", ErrIncomplete
		}
		header := &tar.Header{Name: hash + "." + sig.kind, Mode: 0o444, Size: int64(len(sig.bytes)), ModTime: time.Unix(0, 0), Format: tar.FormatPAX}
		if err := writer.WriteHeader(header); err != nil {
			return "", err
		}
		if _, err := writer.Write(sig.bytes); err != nil {
			return "", err
		}
	}
	if err := writer.Close(); err != nil {
		return "", err
	}
	sum := sha256.Sum256(archive.Bytes())
	name := hex.EncodeToString(sum[:])
	path := s.BundlePath(name)
	if _, err := os.Stat(path); err == nil {
		return name, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return "", err
	}
	return name, os.WriteFile(path, archive.Bytes(), 0o600)
}

// BundlePath serves signatures to machines.
func (s *Store) BundlePath(hash string) string {
	return filepath.Join(s.dir, "bundles", hash+".tar")
}
