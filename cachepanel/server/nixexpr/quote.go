package nixexpr

import "strings"

var escaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "${", `\${`)

// String quotes a Nix string.
func String(text string) string {
	return `"` + escaper.Replace(text) + `"`
}
