package builds

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"

	"cachepanel/realtime"
)

const (
	buildTimeout   = 6 * time.Hour
	stopGrace      = 15 * time.Second
	realBuild      = time.Minute
	maxLogLine     = 8 << 20
	logBufferBytes = 64 << 10
)

var errTimeout = errors.New("bygget brukte mer enn 6 timer")

func (p *Pool) build(ctx context.Context, next claimed) {
	buildCtx, cancel := context.WithTimeout(ctx, buildTimeout)
	defer cancel()
	j := p.track(next, cancel)
	defer p.untrack(next.ID)
	p.announce(next.ID, next.Attr)
	started := time.Now()
	failure := p.run(buildCtx, next, j)
	if ctx.Err() != nil {
		return
	}
	if errors.Is(buildCtx.Err(), context.DeadlineExceeded) {
		failure = errTimeout
	}
	p.finish(ctx, next, j, failure, time.Since(started))
	p.announce(next.ID, next.Attr)
}

func (p *Pool) run(ctx context.Context, next claimed, j *job) (err error) {
	root := p.files.Root(next.ID)
	if err := os.MkdirAll(root, 0o750); err != nil {
		return err
	}
	logFile, err := os.Create(p.files.Log(next.ID))
	if err != nil {
		return err
	}
	log := bufio.NewWriterSize(logFile, logBufferBytes)
	defer func() { err = errors.Join(err, log.Flush(), logFile.Close()) }()

	cmd := exec.CommandContext(ctx, "nix", "build", "--log-format", "internal-json", "-v",
		"--out-link", filepath.Join(root, "result"), next.DrvPath+"^*")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = stopGrace
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	parse := newParser(log, j.progress)
	scanner := bufio.NewScanner(stderr)
	scanner.Buffer(make([]byte, 0, 64<<10), maxLogLine)
	published := time.Now()
	for scanner.Scan() {
		parse.feed(scanner.Text())
		if time.Since(published) < publishTick {
			continue
		}
		published = time.Now()
		j.set(parse.progress)
		p.hub.Publish(realtime.BuildProgress, parse.progress)
	}
	_, _ = io.Copy(io.Discard, stderr)
	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("%w\n%s", err, parse.errors.String())
	}
	return nil
}

// finish records surviving versions.
func (p *Pool) finish(ctx context.Context, next claimed, j *job, failure error, took time.Duration) {
	state, message := "cached", ""
	var closure int64
	switch {
	case j.cancelled.Load():
		state = "cancelled"
	case failure != nil:
		state, message = "failed", failure.Error()
	default:
		closure = p.closureBytes(ctx, next)
	}
	if state != "cached" {
		p.files.removeRoot(next.ID)
	}
	tag, err := p.db.Exec(ctx, `
		UPDATE versions SET state = $2, finished_at = now(), error = nullif($3, ''), closure_bytes = nullif($4, 0)
		WHERE id = $1 AND state = 'building'`, next.ID, state, message, closure)
	if err != nil {
		slog.Error("record build", "version", next.ID, "error", err)
		return
	}
	if tag.RowsAffected() == 0 {
		p.files.Forget(next.ID)
		return
	}
	if state == "cached" && took >= realBuild {
		_, err = p.db.Exec(ctx, `UPDATE packages SET expected_seconds = $2 WHERE attr = $1`, next.Attr, int(took.Seconds()))
	}
	if err != nil {
		slog.Error("record build duration", "version", next.ID, "error", err)
	}
}
