package update

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"time"
)

// The root updater shares these with the panel.
const (
	requestFile = "request.json"
	statusFile  = "status.json"
	idleFile    = "idle"
)

// Request asks root for one panel build.
type Request struct {
	Rev    string `json:"rev"`
	Target string `json:"target"`
}

// Phase is what the root updater is doing.
type Phase string

const (
	Building   Phase = "building"
	Waiting    Phase = "waiting"
	Switching  Phase = "switching"
	Done       Phase = "done"
	Failed     Phase = "failed"
	Superseded Phase = "superseded"
)

// Status is written by the root updater.
type Status struct {
	Phase  Phase     `json:"phase"`
	Rev    string    `json:"rev"`
	Target string    `json:"target"`
	At     time.Time `json:"at"`
	Log    string    `json:"log"`
}

func readJSON(path string, target any) (bool, error) {
	body, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, json.Unmarshal(body, target)
}

// writeAtomic never leaves half a file.
func writeAtomic(path string, body []byte) error {
	partial := path + ".partial"
	if err := os.WriteFile(partial, body, 0o644); err != nil {
		return err
	}
	return os.Rename(partial, path)
}
