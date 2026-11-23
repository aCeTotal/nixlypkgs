package signing

import "time"

// Policy is what releases enforce.
type Policy struct {
	CA          string    `json:"ca"`
	Fingerprint string    `json:"fingerprint"`
	NotAfter    time.Time `json:"notAfter"`
	Rules       []Rule    `json:"rules"`
}

type Rule struct {
	Area string `json:"area"`
	Text string `json:"text"`
}

func policy(ca CA) Policy {
	return Policy{CA: ca.Subject, Fingerprint: ca.Fingerprint, NotAfter: ca.NotAfter, Rules: rules}
}

var rules = []Rule{
	{"Kernel", "Module signatures are mandatory (CONFIG_MODULE_SIG_FORCE); the NixlyOS CA is the only trusted key."},
	{"Kernel", "Lockdown is forced to confidentiality at build time and cannot be lowered from the command line."},
	{"Kernel", "No build-time signing key exists; modules are signed by the CA only after a release passes its checks."},
	{"Boot", "The kernel and systemd-boot EFI binaries carry Authenticode signatures from the NixlyOS CA."},
	{"Boot", "The NixlyOS CA is each machine's platform key; firmware key updates come signed from the panel, so no machine holds a signing key."},
	{"Hibernation", "Images carry an HMAC-SHA256 under a key held in a boot-services-only EFI variable; altered images are refused."},
	{"Hibernation", "/dev/snapshot stays unavailable, so userspace can never supply an image."},
	{"Releases", "Nothing reaches testing or stable unsigned; every release builds on all reference machines and is approved by hand."},
}

// limits are what signatures leave open.
var limits = []string{
	"The initrd and kernel command line carry no signature; lockdown and module enforcement are compiled in, so neither can weaken them.",
	"Anyone at the keyboard can pick an older signed generation; every signed generation enforces the same rules.",
	"Kernel modules no reference machine builds stay unsigned and never load.",
}
