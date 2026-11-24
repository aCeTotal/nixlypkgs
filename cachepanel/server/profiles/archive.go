package profiles

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"slices"
	"strings"
	"time"
)

const treeRoot = "tree/"

// Archive hashes a sorted tar.
func Archive(files []File) (string, []byte, error) {
	files = slices.SortedFunc(slices.Values(files), func(a, b File) int { return strings.Compare(a.Path, b.Path) })
	var plain bytes.Buffer
	writer := tar.NewWriter(&plain)
	epoch := time.Unix(0, 0)
	for _, dir := range folders(files) {
		if err := writer.WriteHeader(&tar.Header{Typeflag: tar.TypeDir, Name: dir, Mode: 0o755, ModTime: epoch, Format: tar.FormatPAX}); err != nil {
			return "", nil, err
		}
	}
	for _, file := range files {
		header := &tar.Header{Typeflag: tar.TypeReg, Name: treeRoot + file.Path, Mode: 0o644, Size: int64(len(file.Content)), ModTime: epoch, Format: tar.FormatPAX}
		if err := writer.WriteHeader(header); err != nil {
			return "", nil, err
		}
		if _, err := writer.Write([]byte(file.Content)); err != nil {
			return "", nil, err
		}
	}
	if err := writer.Close(); err != nil {
		return "", nil, err
	}
	sum := sha256.Sum256(plain.Bytes())
	var packed bytes.Buffer
	compressor, err := gzip.NewWriterLevel(&packed, gzip.BestCompression)
	if err != nil {
		return "", nil, err
	}
	if _, err := compressor.Write(plain.Bytes()); err != nil {
		return "", nil, err
	}
	if err := compressor.Close(); err != nil {
		return "", nil, err
	}
	return hex.EncodeToString(sum[:]), packed.Bytes(), nil
}

// folders lists each file's folder once, sorted.
func folders(files []File) []string {
	dirs := []string{treeRoot}
	for _, file := range files {
		if dir, _, found := strings.Cut(file.Path, "/"); found {
			dirs = append(dirs, treeRoot+dir+"/")
		}
	}
	slices.Sort(dirs)
	return slices.Compact(dirs)
}
