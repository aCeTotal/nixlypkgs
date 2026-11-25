package update

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"time"
)

// Shared with the root updater.
const (
	requestFile = "request.json"
	statusFile  = "status.json"
	idleFile    = "idle"
)

// Request asks root for a build.
type Request struct {
	Rev    string `json:"rev"`
	Target string `json:"target"`
}

// Phase is the updater's step.
type Phase string

const (
	Building   Phase = "building"
	Waiting    Phase = "waiting"
	Switching  Phase = "switching"
	Done       Phase = "done"
	Failed     Phase = "failed"
	Superseded Phase = "superseded"
)

// Status comes from the updater.
type Status struct {
	Phase  Phase     `json:"phase"`
	Rev    string    `json:"rev"`
	Target string    `json:"target"`
	At     time.Time `json:"at"`
	Log    string    `json:"log"`
}

// readJSON skips missing files.
func readJSON(dir, name string, target any) error {
	body, err := fs.ReadFile(os.DirFS(dir), name)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(body, target)
}

// writeAtomic never leaves half a file.
func writeAtomic(path string, body []byte) error {
	partial := path + ".partial"
	if err := os.WriteFile(partial, body, 0o600); err != nil {
		return err
	}
	return os.Rename(partial, path)
}
