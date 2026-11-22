package recipe

import "strings"

var indentedEscaper = strings.NewReplacer("''", "'''", "${", "''${")

// lit shell-quotes inside indented strings.
func lit(text string) string {
	return indentedEscaper.Replace("'" + strings.ReplaceAll(text, "'", `'\''`) + "'")
}

// outPath quotes a path below $out.
func outPath(rel string) string {
	return target("$out/" + rel)
}

// target quotes text; each $out stays live.
func target(text string) string {
	parts := strings.Split(text, "$out")
	for i, part := range parts {
		if part != "" {
			parts[i] = lit(part)
		}
	}
	return strings.Join(parts, `"$out"`)
}
