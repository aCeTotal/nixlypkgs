package analyse

import (
	"bytes"
	"io"
	"strings"
)

// Kind classifies a download.
type Kind int

const (
	Unknown Kind = iota
	ArchiveFile
	DebPackage
	RpmPackage
	AppImageFile
	Executable
)

var archiveSuffixes = []string{".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz", ".tar.zst", ".tzst", ".zip", ".7z", ".tar.lz", ".crate"}

// KindOf sniffs magic bytes, then the name.
func KindOf(file, name string) (Kind, error) {
	f, err := openIn(file)
	if err != nil {
		return Unknown, err
	}
	defer func() { _ = f.Close() }()
	head := make([]byte, 16)
	if _, err := io.ReadFull(f, head); err != nil && err != io.ErrUnexpectedEOF {
		return Unknown, err
	}
	switch {
	case bytes.HasPrefix(head, []byte("\x7fELF")) && bytes.Equal(head[8:10], []byte("AI")):
		return AppImageFile, nil
	case bytes.HasPrefix(head, []byte("\x7fELF")):
		return Executable, nil
	case bytes.HasPrefix(head, []byte("!<arch>\ndebian")):
		return DebPackage, nil
	case bytes.HasPrefix(head, []byte{0xed, 0xab, 0xee, 0xdb}):
		return RpmPackage, nil
	}
	lower := strings.ToLower(name)
	for _, suffix := range archiveSuffixes {
		if strings.HasSuffix(lower, suffix) {
			return ArchiveFile, nil
		}
	}
	if strings.HasSuffix(lower, ".appimage") {
		return AppImageFile, nil
	}
	return Unknown, nil
}
