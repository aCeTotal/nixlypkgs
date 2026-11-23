package profiles

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"maps"
	"slices"
	"strings"

	"cachepanel/nixexpr"
	"cachepanel/signing"
)

// signTree adds boot chain signatures.
func (b *Rebuilder) signTree(ctx context.Context, archive []byte, toplevels []string) (string, []byte, error) {
	files, err := signing.Collect(toplevels)
	if err != nil {
		return "", nil, err
	}
	signed, err := b.Signer.Sign(ctx, toplevels, files)
	if err != nil {
		return "", nil, err
	}
	tree, err := readArchive(archive)
	if err != nil {
		return "", nil, err
	}
	hash, archived, err := Archive(append(tree, File{Path: "signing.nix", Content: signingNix(b.PublicURL, signed.Bundles)}))
	if err != nil {
		return "", nil, err
	}
	_, err = b.DB.Exec(ctx, `INSERT INTO trees (hash, archive, signed_by) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, hash, archived, signed.CA)
	return hash, archived, err
}

// signingNix maps store paths to bundles.
func signingNix(publicURL string, bundles map[string]string) string {
	var out strings.Builder
	out.WriteString("{\n")
	for _, pkg := range slices.Sorted(maps.Keys(bundles)) {
		sum, _ := hex.DecodeString(bundles[pkg])
		fmt.Fprintf(&out, "  %s = {\n    url = %s;\n    hash = %s;\n  };\n", nixexpr.String(pkg),
			nixexpr.String(publicURL+"/api/v1/signatures/"+bundles[pkg]+".tar"),
			nixexpr.String("sha256-"+base64.StdEncoding.EncodeToString(sum)))
	}
	out.WriteString("}\n")
	return out.String()
}
