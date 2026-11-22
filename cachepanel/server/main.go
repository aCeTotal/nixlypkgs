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
	"cachepanel/serve"
)

const usage = "usage: cachepanel <serve|hash-password>"

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
