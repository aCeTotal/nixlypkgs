package analyse

import (
	"os"
	"path/filepath"
)

// openIn opens a file, confined.
func openIn(path string) (*os.File, error) {
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	defer func() { _ = root.Close() }()
	return root.Open(filepath.Base(path))
}

// readIn reads a file, confined.
func readIn(path string) ([]byte, error) {
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	defer func() { _ = root.Close() }()
	return root.ReadFile(filepath.Base(path))
}
