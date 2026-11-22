package recipe

import "strings"

// licenses maps SPDX/Arch names.
var licenses = map[string]string{
	"mit": "mit", "expat": "mit", "x11": "mit",
	"bsd": "bsd3", "bsd-3-clause": "bsd3", "bsd-2-clause": "bsd2", "0bsd": "bsd0",
	"isc": "isc", "apache": "asl20", "apache-2.0": "asl20", "apache 2.0": "asl20",
	"gpl": "gpl2Plus", "gpl2": "gpl2Only", "gpl-2.0": "gpl2Only", "gpl-2.0-only": "gpl2Only", "gpl-2.0-or-later": "gpl2Plus",
	"gpl3": "gpl3Only", "gpl-3.0": "gpl3Only", "gpl-3.0-only": "gpl3Only", "gpl-3.0-or-later": "gpl3Plus",
	"lgpl": "lgpl21Plus", "lgpl2.1": "lgpl21Only", "lgpl-2.1-only": "lgpl21Only", "lgpl-2.1-or-later": "lgpl21Plus",
	"lgpl3": "lgpl3Only", "lgpl-3.0-only": "lgpl3Only", "lgpl-3.0-or-later": "lgpl3Plus",
	"agpl3": "agpl3Only", "agpl-3.0-only": "agpl3Only", "agpl-3.0-or-later": "agpl3Plus",
	"mpl2": "mpl20", "mpl-2.0": "mpl20", "unlicense": "unlicense", "zlib": "zlib", "cc0-1.0": "cc0",
	"bsl-1.0": "boost", "boost": "boost", "wtfpl": "wtfpl", "epl-2.0": "epl20", "psf-2.0": "psfl",
	"ofl-1.1": "ofl", "artistic-2.0": "artistic2", "custom": "unfree", "proprietary": "unfree",
}

// License maps a name, else "".
func License(name string) string {
	key := strings.ToLower(strings.TrimSpace(name))
	if strings.HasPrefix(key, "licenseref-") || strings.HasPrefix(key, "custom:") {
		return "unfree"
	}
	return licenses[key]
}
