package config

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
)

// Config is what boot needs.
type Config struct {
	HTTPAddr    string
	DatabaseURL string
	StateDir    string
	// SourceSeed fills an empty source once.
	SourceSeed string
	Branch     string
	WebRoot    string
	AdminUser  string
	AdminHash  string
	// PublicURL is the machine-facing base.
	PublicURL string
	// SSHRemote is where pushers point git.
	SSHRemote string
	// SSHCommand is the forced git-serve wrapper.
	SSHCommand string
	// CacheDir holds the signed binary cache.
	CacheDir string
	CacheKey string
	// UpdateDir is shared with the root updater.
	UpdateDir string
	// MicrosoftCerts keeps option ROMs booting.
	MicrosoftCerts string
}

var branchPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]*$`)

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:       envOr("CACHEPANEL_HTTP_ADDR", "127.0.0.1:8686"),
		DatabaseURL:    os.Getenv("CACHEPANEL_DATABASE_URL"),
		StateDir:       os.Getenv("CACHEPANEL_STATE_DIR"),
		SourceSeed:     envOr("CACHEPANEL_SOURCE_SEED", "https://github.com/aCeTotal/nixlypkgs"),
		Branch:         envOr("CACHEPANEL_BRANCH", "main"),
		WebRoot:        os.Getenv("CACHEPANEL_WEB_ROOT"),
		AdminUser:      os.Getenv("CACHEPANEL_ADMIN_USER"),
		AdminHash:      os.Getenv("CACHEPANEL_ADMIN_PASSWORD_HASH"),
		PublicURL:      envOr("CACHEPANEL_PUBLIC_URL", "http://127.0.0.1:8686"),
		SSHRemote:      os.Getenv("CACHEPANEL_SSH_REMOTE"),
		SSHCommand:     os.Getenv("CACHEPANEL_SSH_COMMAND"),
		CacheDir:       os.Getenv("CACHEPANEL_CACHE_DIR"),
		CacheKey:       os.Getenv("CACHEPANEL_CACHE_KEY"),
		UpdateDir:      os.Getenv("CACHEPANEL_UPDATE_DIR"),
		MicrosoftCerts: os.Getenv("CACHEPANEL_MICROSOFT_CERTS"),
	}
	if cfg.CacheDir == "" && cfg.StateDir != "" {
		cfg.CacheDir = filepath.Join(cfg.StateDir, "cache")
	}
	var problems []error
	if cfg.DatabaseURL == "" {
		problems = append(problems, errors.New("CACHEPANEL_DATABASE_URL is not set"))
	}
	if cfg.StateDir == "" {
		problems = append(problems, errors.New("CACHEPANEL_STATE_DIR is not set"))
	}
	if !branchPattern.MatchString(cfg.Branch) {
		problems = append(problems, errors.New("CACHEPANEL_BRANCH is not a valid branch name"))
	}
	if (cfg.AdminUser == "") != (cfg.AdminHash == "") {
		problems = append(problems, errors.New("set both CACHEPANEL_ADMIN_USER and CACHEPANEL_ADMIN_PASSWORD_HASH, or neither"))
	}
	return cfg, errors.Join(problems...)
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
