package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"cachepanel/auth"
	"cachepanel/config"
	"cachepanel/database"
	"cachepanel/serve"
	"cachepanel/source"
)

const usage = "usage: cachepanel <serve|hash-password|authorized-keys|git-serve>"

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, nil)))
	if err := run(os.Args[1:]); err != nil {
		slog.Error("cachepanel failed", "error", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) != 1 {
		return errors.New(usage)
	}
	switch args[0] {
	case "serve":
		return serveCommand()
	case "authorized-keys":
		return authorizedKeys()
	case "git-serve":
		return gitServe()
	case "hash-password":
		return hashPassword()
	}
	return errors.New(usage)
}

func serveCommand() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return serve.Run(ctx, cfg)
}

// Reads the password from stdin.
func hashPassword() error {
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	password := strings.TrimRight(line, "\r\n")
	if password == "" {
		return errors.New("empty password on stdin")
	}
	_, err = fmt.Println(auth.HashPassword(password))
	return err
}

// Feeds sshd's AuthorizedKeysCommand.
func authorizedKeys() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx := context.Background()
	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
	return source.Keys{DB: db}.Authorized(ctx, os.Stdout, cfg.SSHCommand)
}

// Runs as each key's forced command.
func gitServe() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	return source.At(cfg).Serve(os.Getenv("SSH_ORIGINAL_COMMAND"))
}
