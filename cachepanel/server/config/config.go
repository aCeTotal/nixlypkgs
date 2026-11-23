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
	Repository  string
	Branch      string
	WebRoot     string
	AdminUser   string
	AdminHash   string
	// PublicURL is the machine-facing base.
	PublicURL string
	// PublishRemote takes recipe commits over SSH.
	PublishRemote string
	PublishKey    string
	// CacheDir holds the signed binary cache.
	CacheDir string
	CacheKey string
}

var branchPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]*$`)

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:      envOr("CACHEPANEL_HTTP_ADDR", "127.0.0.1:8686"),
		DatabaseURL:   os.Getenv("CACHEPANEL_DATABASE_URL"),
		StateDir:      os.Getenv("CACHEPANEL_STATE_DIR"),
		Repository:    envOr("CACHEPANEL_REPOSITORY", "https://github.com/aCeTotal/nixlypkgs"),
		Branch:        envOr("CACHEPANEL_BRANCH", "main"),
		WebRoot:       os.Getenv("CACHEPANEL_WEB_ROOT"),
		AdminUser:     os.Getenv("CACHEPANEL_ADMIN_USER"),
		AdminHash:     os.Getenv("CACHEPANEL_ADMIN_PASSWORD_HASH"),
		PublicURL:     envOr("CACHEPANEL_PUBLIC_URL", "http://127.0.0.1:8686"),
		PublishRemote: os.Getenv("CACHEPANEL_PUBLISH_REMOTE"),
		PublishKey:    os.Getenv("CACHEPANEL_PUBLISH_KEY"),
		CacheDir:      os.Getenv("CACHEPANEL_CACHE_DIR"),
		CacheKey:      os.Getenv("CACHEPANEL_CACHE_KEY"),
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
