package logtail

import "strings"

// Buffer keeps the last bytes written.
type Buffer struct {
	limit int
	text  []byte
}

func New(limit int) *Buffer {
	return &Buffer{limit: limit}
}

func (b *Buffer) Write(chunk []byte) (int, error) {
	b.text = append(b.text, chunk...)
	if excess := len(b.text) - b.limit; excess > 0 {
		b.text = append(b.text[:0], b.text[excess:]...)
	}
	return len(chunk), nil
}

func (b *Buffer) String() string {
	return strings.TrimSpace(string(b.text))
}
