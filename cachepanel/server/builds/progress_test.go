package builds

import (
	"strings"
	"testing"
)

func TestParserTracksProgress(t *testing.T) {
	var log strings.Builder
	p := newParser(&log, Progress{})
	for _, line := range []string{
		`@nix {"action":"start","id":1,"level":0,"parent":0,"text":"","type":104}`,
		`@nix {"action":"start","id":2,"level":0,"parent":0,"text":"","type":103}`,
		`@nix {"action":"start","fields":["/nix/store/aaaa-hello-2.12.drv","",1,1],"id":3,"level":3,"text":"building '/nix/store/aaaa-hello-2.12.drv'","type":105}`,
		`@nix {"action":"result","fields":[1,3,1,0],"id":1,"type":105}`,
		`@nix {"action":"result","fields":[5,9,2,0],"id":2,"type":105}`,
		`@nix {"action":"result","fields":["buildPhase"],"id":3,"type":104}`,
		`@nix {"action":"result","fields":["compiling main.c"],"id":3,"type":101}`,
		`@nix {"action":"msg","level":0,"msg":"\u001b[31;1merror:\u001b[0m builder failed"}`,
		"plain line",
	} {
		p.feed(line)
	}
	got := p.progress
	if got.Builds != (Counter{Done: 1, Expected: 3, Running: 1}) || got.Paths != (Counter{Done: 5, Expected: 9, Running: 2}) {
		t.Errorf("counters: %+v %+v", got.Builds, got.Paths)
	}
	if got.Activity != "Bygger hello-2.12" || got.Phase != "buildPhase" || got.Line != "compiling main.c" {
		t.Errorf("activity: %+v", got)
	}
	if p.errors.String() != "error: builder failed" {
		t.Errorf("errors: %q", p.errors.String())
	}
	if !strings.Contains(log.String(), "compiling main.c\n") || !strings.Contains(log.String(), "plain line\n") {
		t.Errorf("log: %q", log.String())
	}
	p.feed(`@nix {"action":"stop","id":3}`)
	if p.progress.Activity != "" {
		t.Errorf("activity after stop: %q", p.progress.Activity)
	}
}
