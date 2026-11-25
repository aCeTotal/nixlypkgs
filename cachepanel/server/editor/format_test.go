package editor

import (
	"os/exec"
	"testing"
)

func TestFormat(t *testing.T) {
	if _, err := exec.LookPath("nixfmt"); err != nil {
		t.Skip("nixfmt is not installed")
	}
	source, problem, err := format(t.Context(), "{a=1;}")
	if err != nil || problem != "" || source != "{ a = 1; }\n" {
		t.Fatalf("format = %q, %q, %v", source, problem, err)
	}
	if _, problem, err := format(t.Context(), "{ a = ; }"); err != nil || problem != `unexpected "; }", expecting expression` {
		t.Fatalf("broken source: %q, %v", problem, err)
	}
}
