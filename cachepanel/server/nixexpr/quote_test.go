package nixexpr

import "testing"

func TestStringEscapes(t *testing.T) {
	cases := map[string]string{
		`plain`:      `"plain"`,
		`a"b`:        `"a\"b"`,
		`back\slash`: `"back\\slash"`,
		`${inject}`:  `"\${inject}"`,
	}
	for in, want := range cases {
		if got := String(in); got != want {
			t.Errorf("String(%q) = %s, want %s", in, got, want)
		}
	}
}
